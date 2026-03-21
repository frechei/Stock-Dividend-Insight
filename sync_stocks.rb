require 'active_record'
require 'yaml'
require 'faraday'
require 'json'
require 'dotenv/load'
require_relative 'models'

class StockSyncService
  API_URL = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
  
  def initialize(incremental: false)
    @incremental = incremental
  end

  def run
    load_stocks_from_yml
    sync_price_history
    sync_dividends
    calculate_all_yields
  end

  private

  def calculate_all_yields
    puts "Calculating dividend yields for all stocks..."
    Stock.find_each do |stock|
      calculate_stock_yields(stock)
    end
  end

  def calculate_stock_yields(stock)
    latest_price = stock.price_histories.order(date: :desc).first&.close
    return if latest_price.nil? || latest_price == 0

    # 1. 预期股息率 (Expected Dividend Yield)
    # 取最近 12 个月内的所有分红累计 / 最新股价
    one_year_ago = Date.today - 365
    recent_dividends_sum = stock.dividends.where('report_date > ?', one_year_ago).sum(:cash_dividend)
    
    # 如果最近 12 个月没有，尝试取最近一个完整年度的累计
    if recent_dividends_sum == 0
      latest_dividend = stock.dividends.order(report_date: :desc).first
      if latest_dividend
        latest_year = latest_dividend.report_date.year
        recent_dividends_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
      end
    end

    stock.expected_dividend_yield = (recent_dividends_sum / latest_price) * 100 if recent_dividends_sum > 0

    # 2. 历史股息率 (Dividend Yield)
    # 按照用户要求：取股票最后一次分红所属年份的累计股息率
    latest_dividend = stock.dividends.order(report_date: :desc).first
    if latest_dividend
      # 东方财富 API 抓取时已经带了当时的股息率 ZXGXL，但为了准确性，我们根据累计分红计算
      latest_year = latest_dividend.report_date.year
      year_dividends_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
      
      # 这里使用最新股价来计算当前的“历史分红收益率”
      stock.dividend_yield = (year_dividends_sum / latest_price) * 100 if year_dividends_sum > 0
    end

    stock.save! if stock.changed?
  end

  def sync_dividends
    Stock.find_each do |stock|
      puts "Syncing dividends for #{stock.name} (#{stock.secid})..."
      begin
        fetch_and_save_dividends(stock)
      rescue => e
        puts "Error syncing dividends for #{stock.name}: #{e.message}"
      end
      sleep(rand(1.0..2.0))
    end
  end

  def fetch_and_save_dividends(stock)
    url = "https://datacenter-web.eastmoney.com/api/data/get"
    params = {
      type: "RPT_LICO_FN_CPD",
      sty: "ALL",
      filter: "(SECURITY_CODE=\"#{stock.code}\")",
      p: 1,
      ps: 50
    }

    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'application/json'
    }

    conn = Faraday.new(url: url) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    response = conn.get('', params, headers)
    
    unless response.success?
      puts "Dividend API request failed for #{stock.name}: #{response.status}"
      return
    end

    data = JSON.parse(response.body)
    results = data.dig('result', 'data') || []

    if results.empty?
      puts "No dividend data found for #{stock.name}"
      return
    end

    records_created = 0
    results.each do |item|
      # 报告期
      report_date = Date.parse(item['REPORTDATE']) rescue nil
      next unless report_date

      # 分红方案描述
      description = item['ASSIGNDSCRPT']
      next if description.nil? || description == "不分配" || description == "无分红"

      # 解析分红方案
      # 10派1.60元 -> cash_dividend = 0.16
      # 10送2转3派1.50元 -> bonus = 0.2, rights = 0.3, cash = 0.15
      base = 10.0
      if description =~ /(\d+)派|送|转/
        base = $1.to_f
      end

      cash = 0.0
      bonus = 0.0
      rights = 0.0

      if base > 0
        if description =~ /派([\d\.]+)元/
          cash = $1.to_f / base
        end
        if description =~ /送([\d\.]+)股/
          bonus = $1.to_f / base
        end
        if description =~ /转([\d\.]+)股/
          rights = $1.to_f / base
        end
      end

      div = Dividend.find_or_initialize_by(stock_id: stock.id, report_date: report_date)
      div.notice_date = Date.parse(item['NOTICE_DATE']) rescue nil
      div.plan_description = description
      
      # 确保数值字段是有限的
      div.cash_dividend = cash.finite? ? cash : 0
      div.bonus_issue = bonus.finite? ? bonus : 0
      div.rights_issue = rights.finite? ? rights : 0
      
      # 处理股息率，确保是有限数值
      yield_val = item['ZXGXL'].to_f
      div.dividend_yield = yield_val.finite? ? yield_val : nil
      
      if div.changed?
        div.save!
        records_created += 1
      end
    end
    
    puts "Saved #{records_created} dividend records for #{stock.name}."
  end

  def load_stocks_from_yml
    puts "Loading stocks from stocks.yml..."
    stocks_data = YAML.load_file('stocks.yml')
    
    stocks_data.each do |data|
      next unless data['secid'] && data['name']
      
      market_id, code = data['secid'].split('.')
      
      Stock.find_or_create_by!(secid: data['secid']) do |s|
        s.name = data['name']
        s.market_id = market_id.to_i
        s.code = code
      end
    end
    puts "Loaded #{Stock.count} stocks."
  end

  def sync_price_history
    Stock.find_each do |stock|
      puts "Syncing price history for #{stock.name} (#{stock.secid})..."
      
      retries = 3
      begin
        fetch_and_save_kline(stock)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
        if retries > 0
          retries -= 1
          wait_time = (4 - retries) * 5 + rand(1..3)
          puts "Network error syncing #{stock.name}: #{e.message}. Retrying in #{wait_time}s... (#{retries} left)"
          sleep(wait_time)
          retry
        else
          puts "Failed to sync #{stock.name} after retries due to network error: #{e.message}"
        end
      rescue => e
        puts "Error syncing #{stock.name}: #{e.message}"
      end
      
      # 频率控制，增加随机性
      sleep_time = rand(1.0..3.0)
      sleep(sleep_time)
    end
  end

  def fetch_and_save_kline(stock)
    # 转换 secid 为新浪格式 (例如 1.601398 -> sh601398)
    market_prefix = stock.market_id == 1 ? 'sh' : 'sz'
    symbol = "#{market_prefix}#{stock.code}"
    
    # 默认抓取 1000 条数据，如果是增量更新，则抓取 10 条
    datalen = @incremental ? 10 : 1000

    url = "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData"
    params = {
      symbol: symbol,
      scale: 240, # 日K
      ma: 'no',
      datalen: datalen
    }

    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => '*/*'
    }

    conn = Faraday.new(url: url) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    response = conn.get('', params, headers)
    
    unless response.success?
      puts "Sina API request failed for #{stock.name}: #{response.status}"
      return
    end

    begin
      # 新浪返回的是 GBK 编码或者 JSON 字符串
      data = JSON.parse(response.body)
    rescue => e
      puts "Failed to parse JSON for #{stock.name}: #{e.message}"
      return
    end

    if data.empty?
      puts "No kline data found for #{stock.name}"
      return
    end

    records_created = 0
    data.each do |item|
      # 新浪 API 返回格式: 
      # {"day":"2026-03-20","open":"10.870","high":"10.940","low":"10.760","close":"10.770","volume":"83408256"}
      date = Date.parse(item['day'])
      
      ph = PriceHistory.find_or_initialize_by(stock_id: stock.id, date: date)
      ph.open = item['open'].to_f
      ph.close = item['close'].to_f
      ph.high = item['high'].to_f
      ph.low = item['low'].to_f
      ph.volume = item['volume'].to_i
      # 新浪此接口不提供成交额和振幅，如需可后期计算
      
      if ph.changed?
        ph.save!
        records_created += 1
      end
    end
    
    puts "Saved #{records_created} records for #{stock.name}."
  end
end

if __FILE__ == $0
  incremental = ARGV.include?('--incremental')
  StockSyncService.new(incremental: incremental).run
end
