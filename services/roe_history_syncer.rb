require 'faraday'
require 'faraday/retry'
require 'json'
require 'date'

class RoeHistorySyncer
  def initialize(scope: Stock.all, years: 12, sleep_range: (0.04..0.10))
    @scope = scope
    @years = years.to_i
    @years = 12 if @years <= 0
    @sleep_range = sleep_range
  end

  def sync
    conn = Faraday.new do |f|
      f.request :url_encoded
      f.request :retry, max: 3, interval: 0.05,
                       interval_randomness: 0.5, backoff_factor: 2,
                       exceptions: [Faraday::Error, JSON::ParserError]
      f.adapter Faraday.default_adapter
    end

    @scope.order(:id).find_each do |stock|
      sync_one(conn, stock)
      sleep(rand(@sleep_range)) if @sleep_range
    end
  end

  private

  def sync_one(conn, stock)
    code = stock.code.to_s.rjust(6, '0')
    from_date = Date.today << (@years * 12)
    from_str = from_date.strftime('%Y-%m-%d')

    page = 1
    page_size = 50
    total_pages = 1
    latest_row = nil

    while page <= total_pages
      resp = conn.get('https://datacenter-web.eastmoney.com/api/data/v1/get', {
        reportName: 'RPT_F10_FINANCE_MAINFINADATA',
        columns: 'SECURITY_CODE,REPORT_DATE,REPORT_TYPE,REPORT_YEAR,ROEJQ,ROEKCJQ,NOTICE_DATE,UPDATE_DATE',
        pageNumber: page,
        pageSize: page_size,
        sortColumns: 'REPORT_DATE',
        sortTypes: -1,
        source: 'WEB',
        client: 'WEB',
        filter: "(SECURITY_CODE=\"#{code}\")(REPORT_DATE>='#{from_str}')"
      }, {
        'User-Agent' => 'Mozilla/5.0',
        'Referer' => 'https://data.eastmoney.com/',
        'Connection' => 'close'
      }) do |req|
        req.options.timeout = 15
        req.options.open_timeout = 8
      end
      return unless resp.success?

      parsed = JSON.parse(resp.body) rescue nil
      return unless parsed && parsed['code'].to_i == 0

      result = parsed['result'] || {}
      total_pages = result['pages'].to_i
      total_pages = 1 if total_pages <= 0
      rows = result['data']
      break unless rows.is_a?(Array) && !rows.empty?

      latest_row ||= rows.first

      rows.each do |row|
        report_date = parse_date(row['REPORT_DATE'])
        next unless report_date

        rh = stock.roe_histories.find_or_initialize_by(report_date: report_date)
        rh.report_type = row['REPORT_TYPE']
        rh.report_year = row['REPORT_YEAR']
        rh.roe_jq = parse_decimal(row['ROEJQ'])
        rh.roe_kc_jq = parse_decimal(row['ROEKCJQ'])
        rh.notice_date = parse_date(row['NOTICE_DATE'])
        rh.update_date = parse_date(row['UPDATE_DATE'])
        rh.save! if rh.changed?
      end

      page += 1
    end

    return unless latest_row

    roe_jq = parse_decimal(latest_row['ROEJQ'])
    roe_kc_jq = parse_decimal(latest_row['ROEKCJQ'])

    flags = compute_roe_5y_flags(stock)
    stock.update!(
      roe_jq: roe_jq,
      roe_kc_jq: roe_kc_jq,
      roe_report_date: parse_date(latest_row['REPORT_DATE']),
      roe_report_type: latest_row['REPORT_TYPE'].to_s,
      roe_level: roe_level_for(roe_jq),
      roe_5y_avg_ge_12: flags[:roe_5y_avg_ge_12],
      roe_5y_min_ge_8: flags[:roe_5y_min_ge_8]
    )
  rescue Faraday::Error, StandardError => e
    puts "roe_sync_error code=#{stock.code} error=#{e.class}: #{e.message}"
    nil
  end

  def compute_roe_5y_flags(stock)
    rows =
      stock
        .roe_histories
        .where(report_type: '年报')
        .where.not(roe_jq: nil)
        .order(report_date: :desc)
        .limit(5)
        .pluck(:roe_jq)
        .map(&:to_f)

    return { roe_5y_avg_ge_12: false, roe_5y_min_ge_8: false } if rows.size < 5

    avg = rows.sum / rows.size.to_f
    min = rows.min
    { roe_5y_avg_ge_12: avg >= 12.0, roe_5y_min_ge_8: min >= 8.0 }
  end

  def roe_level_for(roe_jq)
    return nil if roe_jq.nil?
    v = roe_jq.to_f
    return 3 if v > 20.0
    return 2 if v > 15.0
    1
  end

  def parse_decimal(value)
    return nil if value.nil?
    s = value.to_s.strip
    return nil if s.empty? || s == '-'
    Float(s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_date(value)
    s = value.to_s.strip
    return nil if s.empty?
    Date.parse(s)
  rescue ArgumentError
    nil
  end
end
