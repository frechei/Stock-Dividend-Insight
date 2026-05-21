require 'date'
require 'faraday'
require 'faraday/retry'
require 'faraday/net_http_persistent'
require 'json'

class ValuationHistorySyncer
  def initialize(scope: Stock.all, years: 10, sleep_range: (0.05..0.12), force: false)
    @scope = scope
    @years = years.to_i
    @sleep_range = sleep_range
    @force = force
  end

  def sync
    conn = Faraday.new do |f|
      f.request :url_encoded
      f.request :retry, max: 3, interval: 0.05,
                       interval_randomness: 0.5, backoff_factor: 2,
                       exceptions: [Faraday::Error, JSON::ParserError]
      f.adapter :net_http_persistent
    end

    @scope.find_each do |stock|
      next unless stock.code && stock.code.to_s.match?(/^\d{6}$/)
      sync_one(conn, stock)
      sleep(rand(@sleep_range)) if @sleep_range
    end
  end

  private

  def sync_one(conn, stock)
    from_date = Date.today << (@years * 12)
    from_str = from_date.strftime('%Y-%m-%d')
    code = stock.code.to_s.rjust(6, '0')

    page = 1
    page_size = 5000
    total_pages = 1
    updated = 0

    while page <= total_pages
      resp = conn.get('https://datacenter-web.eastmoney.com/api/data/v1/get', {
        reportName: 'RPT_VALUEANALYSIS_DET',
        columns: 'ALL',
        pageNumber: page,
        pageSize: page_size,
        sortColumns: 'TRADE_DATE',
        sortTypes: 1,
        source: 'WEB',
        client: 'WEB',
        filter: "(SECURITY_CODE=\"#{code}\")(TRADE_DATE>='#{from_str}')"
      }, { 'User-Agent' => 'Mozilla/5.0', 'Referer' => 'https://data.eastmoney.com/' }) do |req|
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

      rows.each do |row|
        trade_date = row['TRADE_DATE'].to_s
        date = Date.parse(trade_date)

        ph = stock.price_histories.find_or_initialize_by(date: date)
        close_price = row['CLOSE_PRICE']
        pe_ttm = row['PE_TTM']
        pb = row['PB_MRQ']

        ph.close = close_price.to_f if @force || ph.close.nil?
        ph.pe_ttm = pe_ttm.to_f if pe_ttm && (@force || ph.pe_ttm.nil?)
        ph.pb = pb.to_f if pb && (@force || ph.pb.nil?)

        if ph.changed?
          ph.save!
          updated += 1
        end
      rescue ArgumentError
        next
      end

      page += 1
      sleep(0.05 + rand(0.0..0.08))
    end

    updated
  rescue Faraday::Error, StandardError => e
    puts "valuation_history_sync_error code=#{stock.code} error=#{e.class}: #{e.message}"
    nil
  end
end
