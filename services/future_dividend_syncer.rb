require 'faraday'
require 'faraday/retry'
require 'faraday/net_http_persistent'
require 'json'
require 'date'
require 'digest'

class FutureDividendSyncer
  def initialize(days_back: 30, days_ahead: 365, sleep_range: (0.04..0.10))
    @days_back = days_back.to_i
    @days_ahead = days_ahead.to_i
    @sleep_range = sleep_range
  end

  def sync
    start_date = Date.today - @days_back
    end_date = Date.today + @days_ahead

    stock_by_code =
      Stock
        .where(asset_type: 'stock')
        .pluck(:id, :code, :name)
        .each_with_object({}) do |(id, code, name), h|
          h[code.to_s.rjust(6, '0')] = { id: id, name: name.to_s }
        end

    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'application/json'
    }

    conn =
      Faraday.new(url: 'https://datacenter-web.eastmoney.com') do |f|
        f.request :url_encoded
        f.request :retry, max: 3, interval: 0.05,
                         interval_randomness: 0.5, backoff_factor: 2,
                         exceptions: [Faraday::Error, JSON::ParserError]
        f.options.timeout = 15
        f.options.open_timeout = 8
        f.adapter :net_http_persistent
      end

    all_rows = []
    page_number = 1
    loop do
      params = {
        reportName: 'RPT_SHAREBONUS_DET',
        columns: 'ALL',
        pageNumber: page_number,
        pageSize: 2000,
        sortColumns: 'EX_DIVIDEND_DATE',
        sortTypes: '1',
        source: 'WEB',
        client: 'WEB',
        filter: "(EX_DIVIDEND_DATE>='#{start_date.strftime('%Y-%m-%d')}') AND (EX_DIVIDEND_DATE<='#{end_date.strftime('%Y-%m-%d')}')"
      }

      begin
        resp = conn.get('/api/data/v1/get', params, headers)
        json = JSON.parse(resp.body) rescue {}
        data = json.dig('result', 'data') || []
        break if data.empty?
        all_rows.concat(data)
        page_number += 1
        break if page_number > 80
        sleep(rand(@sleep_range)) if @sleep_range
      rescue Faraday::Error, StandardError => e
        puts "future_dividend_fetch_error page=#{page_number} error=#{e.class}: #{e.message}"
        break
      end
    end

    now = Time.now
    upsert_rows =
      all_rows.filter_map do |row|
        code = row['SECURITY_CODE'].to_s.rjust(6, '0')
        info = stock_by_code[code]
        next unless info

        ex_date = parse_date(row['EX_DIVIDEND_DATE'])
        next unless ex_date
        next if ex_date < start_date || ex_date > end_date

        plan = row['IMPL_PLAN_PROFILE'].to_s.strip
        next if plan.empty?

        equity_record_date = parse_date(row['EQUITY_RECORD_DATE'])
        notice_date = parse_date(row['NOTICE_DATE']) || parse_date(row['PLAN_NOTICE_DATE']) || parse_date(row['PUBLISH_DATE'])
        dividend_yield_pct = row['DIVIDENT_RATIO'].nil? ? nil : (row['DIVIDENT_RATIO'].to_f * 100.0)
        cash_per_share = parse_cash_dividend_per_share(plan)
        progress = row['ASSIGN_PROGRESS'].to_s.strip
        security_name = row['SECURITY_NAME_ABBR'].to_s.strip
        security_name = info[:name] if security_name.empty?

        unique_key = Digest::SHA1.hexdigest([code, ex_date, equity_record_date, plan].join('|'))
        {
          unique_key: unique_key,
          stock_id: info[:id],
          security_code: code,
          security_name: security_name,
          ex_dividend_date: ex_date,
          equity_record_date: equity_record_date,
          notice_date: notice_date,
          progress: progress.empty? ? nil : progress,
          plan_description: plan,
          dividend_yield_pct: dividend_yield_pct,
          cash_dividend_per_share: cash_per_share,
          created_at: now,
          updated_at: now
        }
      end

    FutureDividend.upsert_all(upsert_rows, unique_by: :index_future_dividends_on_unique_key) if upsert_rows.any?

    stale_cutoff = Date.today - 3650
    FutureDividend.where('ex_dividend_date < ?', stale_cutoff).delete_all
  end

  private

  def parse_date(value)
    return nil if value.nil?
    s = value.to_s.strip
    return nil if s.empty?
    Date.parse(s) rescue nil
  end

  def parse_cash_dividend_per_share(plan_text)
    s = plan_text.to_s
    return nil if s.strip.empty?

    if (m = s.match(/每?\s*(\d+)\s*股\s*派\s*([\d\.]+)\s*元/))
      base = m[1].to_f
      amt = m[2].to_f
      return nil if base <= 0 || amt <= 0
      return amt / base
    end
    if (m = s.match(/(\d+)\s*派\s*([\d\.]+)\s*元/))
      base = m[1].to_f
      amt = m[2].to_f
      return nil if base <= 0 || amt <= 0
      return amt / base
    end
    nil
  end
end
