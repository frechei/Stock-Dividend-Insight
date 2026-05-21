require 'yaml'
require 'json'
require 'date'
require 'time'
require 'fileutils'
require 'digest'
require 'net/http'
require 'uri'

ROOT_DIR = File.expand_path('..', __dir__)
IN_YML = File.join(ROOT_DIR, 'stocks-dividend-gt3.yml')
OUT_DIR = File.join(ROOT_DIR, 'docs', 'gt3')
OUT_HTML = File.join(OUT_DIR, 'index.html')
OUT_YML = File.join(OUT_DIR, 'data.yml')

FileUtils.mkdir_p(OUT_DIR)

def http_get_json(url, params: {}, headers: {}, timeout: 15, open_timeout: 8, attempts: 3)
  uri = URI(url)
  uri.query = URI.encode_www_form(params) if params && !params.empty?
  last_error = nil
  attempts.times do |i|
    begin
      req = Net::HTTP::Get.new(uri)
      headers.each { |k, v| req[k] = v }
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: open_timeout, read_timeout: timeout) do |http|
        res = http.request(req)
        return nil unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      end
    rescue StandardError => e
      last_error = e
      sleep(0.3 * (i + 1))
    end
  end
  raise last_error if last_error
  nil
end

def http_get_text(url, headers: {}, timeout: 12, open_timeout: 6, attempts: 3)
  uri = URI(url)
  last_error = nil
  attempts.times do |i|
    begin
      req = Net::HTTP::Get.new(uri)
      headers.each { |k, v| req[k] = v }
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: open_timeout, read_timeout: timeout) do |http|
        res = http.request(req)
        return nil unless res.is_a?(Net::HTTPSuccess)
        res.body.to_s
      end
    rescue StandardError => e
      last_error = e
      sleep(0.3 * (i + 1))
    end
  end
  raise last_error if last_error
  nil
end

def parse_date(value)
  return nil if value.nil?
  s = value.to_s.strip
  return nil if s.empty?
  Date.parse(s) rescue nil
end

def clamp(v, lo, hi)
  x = v.to_f
  return lo unless x.finite?
  return lo if x < lo
  return hi if x > hi
  x
end

def clamp01(v)
  clamp(v, 0.0, 1.0)
end

def pe_level_for(pe_ttm)
  return nil if pe_ttm.nil?
  v = pe_ttm.to_f
  return nil unless v.finite?
  return 1 if v < 0
  return 2 if v < 10
  return 3 if v < 20
  return 4 if v < 30
  return 5 if v < 50
  return 6 if v < 100
  7
end

def pb_level_for(pb)
  return nil if pb.nil?
  v = pb.to_f
  return nil unless v.finite? && v > 0
  return 1 if v <= 0.8
  return 2 if v <= 1.5
  return 3 if v <= 3
  return 4 if v <= 6
  return 5 if v <= 10
  6
end

def roe_level_for(roe_jq)
  return nil if roe_jq.nil?
  v = roe_jq.to_f
  return nil unless v.finite?
  return 3 if v > 20.0
  return 2 if v > 15.0
  1
end

def peg_level_for(peg, growth_pct)
  g = growth_pct.to_f
  return 5 if g.finite? && g < 0
  p = peg.to_f
  return nil unless p.finite? && p > 0
  return 1 if p < 0.5
  return 2 if p < 1.0
  return 3 if p <= 1.5
  4
end

def score_dividend_payout_ratio(value)
  return 0.5 if value.nil?
  r = value.to_f
  return 0.5 unless r.finite?
  return 0.3 if r <= 0
  return 0.6 if r < 20
  return 1.0 if r <= 60
  return 0.7 if r <= 100
  return 0.4 if r <= 150
  0.2
end

def score_pe_level(level)
  return 0.5 if level.nil?
  case level.to_i
  when 2 then 1.0
  when 3 then 0.85
  when 4 then 0.60
  when 5 then 0.40
  when 6 then 0.20
  when 7 then 0.05
  when 1 then 0.10
  else 0.5
  end
end

def score_pb_level(level)
  return 0.5 if level.nil?
  case level.to_i
  when 1 then 1.0
  when 2 then 0.85
  when 3 then 0.60
  when 4 then 0.40
  when 5 then 0.20
  when 6 then 0.05
  else 0.5
  end
end

def score_peg_level(level)
  return 0.5 if level.nil?
  case level.to_i
  when 1 then 1.0
  when 2 then 0.85
  when 3 then 0.60
  when 4 then 0.30
  when 5 then 0.10
  else 0.5
  end
end

def score_asset_liability_ratio(value)
  return 0.5 if value.nil?
  r = value.to_f
  return 0.5 unless r.finite?
  return 1.0 if r <= 0
  return 0.0 if r >= 80.0
  clamp01(1.0 - (r / 80.0))
end

def score_fcf_yield(value)
  return 0.5 if value.nil?
  y = value.to_f
  return 0.5 unless y.finite?
  clamp01(y / 10.0)
end

def score_roe_level(level)
  return 0.5 if level.nil?
  case level.to_i
  when 1 then 0.40
  when 2 then 0.70
  when 3 then 1.00
  else 0.5
  end
end

def score_price_position(value)
  return 0.5 if value.nil?
  p = value.to_f
  return 0.5 unless p.finite?
  clamp01(1.0 - p)
end

def buy_score_5(stock)
  weights = {
    dividend_payout_ratio: 0.15,
    pe_level: 0.15,
    pb_level: 0.15,
    peg_level: 0.10,
    asset_liability_ratio: 0.10,
    fcf_yield: 0.10,
    roe_level: 0.15,
    price_position: 0.10
  }

  s = 0.0
  s += weights[:dividend_payout_ratio] * score_dividend_payout_ratio(stock[:dividend_payout_ratio])
  s += weights[:pe_level] * score_pe_level(stock[:pe_level])
  s += weights[:pb_level] * score_pb_level(stock[:pb_level])
  s += weights[:peg_level] * score_peg_level(stock[:peg_level])
  s += weights[:asset_liability_ratio] * score_asset_liability_ratio(stock[:asset_liability_ratio])
  s += weights[:fcf_yield] * score_fcf_yield(stock[:fcf_yield])
  s += weights[:roe_level] * score_roe_level(stock[:roe_level])
  s += weights[:price_position] * score_price_position(stock[:price_position])

  raw = 1.0 + 4.0 * clamp01(s)
  rounded = (clamp(raw, 1.0, 5.0) * 2.0).round / 2.0
  clamp(rounded, 1.0, 5.0).round(2)
end

def format_num(v, precision = 2)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f", x)
end

def format_pct(v, precision = 2)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f%%", x)
end

def format_ratio_pct(v, precision = 0)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f%%", x * 100.0)
end

def format_score_half(v)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  r = (x * 2.0).round / 2.0
  ((r - r.round).abs < 1e-9) ? r.round.to_s : format('%.1f', r)
end

def percentile_for_value(sorted_values, current)
  return nil if sorted_values.nil? || sorted_values.empty? || current.nil?
  c = current.to_f
  return nil unless c.finite? && c > 0
  arr = sorted_values
  return 0.5 if arr.size <= 1
  idx = arr.bsearch_index { |x| x >= c } || (arr.size - 1)
  (idx.to_f / (arr.size - 1).to_f).clamp(0.0, 1.0)
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

raise "missing #{IN_YML}" unless File.exist?(IN_YML)
data = YAML.load_file(IN_YML)
list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])
stocks =
  list.filter_map do |row|
    code = row['code'].to_s.strip.rjust(6, '0')
    next unless code.match?(/^\d{6}$/)
    name = row['name'].to_s.strip
    next if name.empty?
    { code: code, name: name, categories: Array(row['categories']).map(&:to_s) }
  end

ua_headers = {
  'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept' => 'application/json',
  'Connection' => 'close'
}

quote_headers = ua_headers.merge('Referer' => 'https://gu.qq.com/')

code_to_metrics = stocks.each_with_object({}) { |s, h| h[s[:code]] = { code: s[:code], name: s[:name], categories: s[:categories] } }

symbols = stocks.map { |s| (s[:code].start_with?('6') ? 'sh' : 'sz') + s[:code] }
symbols.each_slice(50) do |batch|
  body = http_get_text('https://qt.gtimg.cn/q=' + batch.join(','), headers: quote_headers)
  next unless body
  body.lines.each do |line|
    m = line.match(/\Av_(?<symbol>(?:sz|sh)\d{6})=\"(?<data>.*)\";?\s*\z/)
    next unless m
    sym = m[:symbol]
    code = sym[-6, 6]
    fields = m[:data].split('~')
    price = fields[3].to_f
    pe_ttm = fields[39].to_f
    pb = fields[46].to_f
    total_mv_yi = fields[45].to_f
    next unless code_to_metrics[code]
    code_to_metrics[code][:current_price] = (price > 0 ? price : nil)
    code_to_metrics[code][:pe_ttm] = (pe_ttm > 0 ? pe_ttm : nil)
    code_to_metrics[code][:pb] = (pb > 0 ? pb : nil)
    code_to_metrics[code][:market_cap] = (total_mv_yi > 0 ? (total_mv_yi * 100_000_000.0) : nil)
  end
  sleep(0.08)
end

stocks.each do |s|
  code = s[:code]
  m = code_to_metrics[code]
  next unless m
  resp = http_get_json('https://datacenter-web.eastmoney.com/api/data/v1/get', params: {
    reportName: 'RPT_F10_FINANCE_MAINFINADATA',
    columns: 'ALL',
    pageNumber: 1,
    pageSize: 1,
    sortColumns: 'REPORT_DATE',
    sortTypes: -1,
    source: 'WEB',
    client: 'WEB',
    filter: "(SECURITY_CODE=\"#{code}\")"
  }, headers: ua_headers)
  row = resp&.dig('result', 'data')&.first
  next unless row.is_a?(Hash)
  total_assets = row['TOTAL_ASSETS_PK']
  total_liabilities = row['LIABILITY']
  assets = total_assets.is_a?(Numeric) ? total_assets.to_f : (Float(total_assets.to_s) rescue nil)
  liab = total_liabilities.is_a?(Numeric) ? total_liabilities.to_f : (Float(total_liabilities.to_s) rescue nil)
  if assets && assets > 0 && liab && liab >= 0
    m[:asset_liability_ratio] = (liab / assets) * 100.0
  end
  roe = row['ROEJQ']
  roe = roe.is_a?(Numeric) ? roe.to_f : (Float(roe.to_s) rescue nil)
  m[:roe_jq] = roe if roe && roe.finite?
  m[:roe_level] = roe_level_for(m[:roe_jq])

  growth = row['DJD_DEDUCTDPNP_YOY']
  growth = growth.is_a?(Numeric) ? growth.to_f : (Float(growth.to_s) rescue nil)
  growth ||= (row['DJD_DPNP_YOY'].is_a?(Numeric) ? row['DJD_DPNP_YOY'].to_f : (Float(row['DJD_DPNP_YOY'].to_s) rescue nil))
  growth = nil unless growth && growth.finite?
  pe = m[:pe_ttm]
  if pe && growth && growth > 0
    m[:peg] = pe.to_f / growth.to_f
  end
  m[:peg_level] = peg_level_for(m[:peg], growth.to_f) if m[:peg]

  fcff = row['FCFF_BACK']
  fcff = fcff.is_a?(Numeric) ? fcff.to_f : (Float(fcff.to_s) rescue nil)
  if fcff && fcff.finite? && m[:market_cap] && m[:market_cap].to_f > 0
    m[:fcf_yield] = (fcff / m[:market_cap].to_f) * 100.0
  end
  sleep(0.06)
end

from_date = (Date.today << 120).strftime('%Y-%m-%d')
stocks.each do |s|
  code = s[:code]
  m = code_to_metrics[code]
  next unless m
  resp = http_get_json('https://datacenter-web.eastmoney.com/api/data/v1/get', params: {
    reportName: 'RPT_VALUEANALYSIS_DET',
    columns: 'TRADE_DATE,CLOSE_PRICE,PE_TTM,PB_MRQ',
    pageNumber: 1,
    pageSize: 5000,
    sortColumns: 'TRADE_DATE',
    sortTypes: 1,
    source: 'WEB',
    client: 'WEB',
    filter: "(SECURITY_CODE=\"#{code}\")(TRADE_DATE>='#{from_date}')"
  }, headers: ua_headers, timeout: 20, open_timeout: 10)
  rows = resp&.dig('result', 'data')
  next unless rows.is_a?(Array) && rows.any?

  closes = []
  pes = []
  pbs = []
  closes_by_year = Hash.new { |h, k| h[k] = [] }

  rows.each do |row|
    d = parse_date(row['TRADE_DATE'])
    next unless d
    close = row['CLOSE_PRICE']
    close = close.is_a?(Numeric) ? close.to_f : (Float(close.to_s) rescue nil)
    if close && close.finite? && close > 0
      closes << close
      closes_by_year[d.year] << close
    end
    pe = row['PE_TTM']
    pe = pe.is_a?(Numeric) ? pe.to_f : (Float(pe.to_s) rescue nil)
    pes << pe if pe && pe.finite? && pe > 0
    pb = row['PB_MRQ']
    pb = pb.is_a?(Numeric) ? pb.to_f : (Float(pb.to_s) rescue nil)
    pbs << pb if pb && pb.finite? && pb > 0
  end

  closes.sort!
  pes.sort!
  pbs.sort!

  price = m[:current_price]
  pe_now = m[:pe_ttm]
  pb_now = m[:pb]

  m[:price_position] = closes.size >= 20 ? percentile_for_value(closes, price) : nil
  m[:pe_percentile] = pes.size >= 20 ? percentile_for_value(pes, pe_now) : nil
  m[:pb_percentile] = pbs.size >= 20 ? percentile_for_value(pbs, pb_now) : nil

  m[:pe_level] = pe_level_for(pe_now)
  m[:pb_level] = pb_level_for(pb_now)

  m[:avg_close_by_year] = closes_by_year.transform_values { |arr| arr.empty? ? nil : (arr.sum / arr.size.to_f) }
  sleep(0.06)
end

stocks.each do |s|
  code = s[:code]
  m = code_to_metrics[code]
  next unless m
  resp = http_get_json('https://datacenter-web.eastmoney.com/api/data/get', params: {
    type: 'RPT_LICO_FN_CPD',
    sty: 'ALL',
    filter: "(SECURITY_CODE=\"#{code}\")",
    p: 1,
    ps: 50
  }, headers: ua_headers, timeout: 20, open_timeout: 10)
  rows = resp&.dig('result', 'data')
  next unless rows.is_a?(Array) && rows.any?

  year_sum = Hash.new(0.0)
  rows.each do |item|
    report_date = parse_date(item['REPORTDATE'])
    next unless report_date
    desc = item['ASSIGNDSCRPT'].to_s
    next if desc.strip.empty?
    cash = parse_cash_dividend_per_share(desc)
    next unless cash && cash.finite? && cash > 0
    year_sum[report_date.year] += cash
  end

  years = year_sum.keys.sort
  latest_year = years.reverse.find { |y| year_sum[y].to_f > 0 }
  if latest_year
    dps = year_sum[latest_year].to_f
    price = m[:current_price].to_f
    price = nil if !price.finite? || price <= 0
    m[:dividend_cash_per_share_latest_year] = dps
    m[:dividend_cash_per_share_year] = latest_year
    m[:dividend_yield] = (price && price > 0) ? (dps / price) * 100.0 : nil

    yields = []
    [latest_year - 2, latest_year - 1, latest_year].each do |y|
      dps_y = year_sum[y].to_f
      avg_close = m[:avg_close_by_year].is_a?(Hash) ? m[:avg_close_by_year][y] : nil
      if dps_y <= 0 || avg_close.nil? || avg_close.to_f <= 0
        yields = []
        break
      end
      yields << (dps_y / avg_close.to_f) * 100.0
    end
    m[:avg_dividend_yield_3y] = yields.size == 3 ? (yields.sum / 3.0) : nil
  end
  sleep(0.06)
end

code_to_metrics.each_value do |m|
  dy = m[:dividend_yield]
  pe = m[:pe_ttm]
  if dy && pe && dy.to_f >= 0 && pe.to_f > 0
    m[:dividend_payout_ratio] = dy.to_f * pe.to_f
  end
  m[:buy_score] = buy_score_5(m)

  dps = m[:dividend_cash_per_share_latest_year]
  price = m[:current_price]
  if dps && dps.to_f > 0 && price && price.to_f > 0
    buy5 = dps.to_f / 0.05
    buy6 = dps.to_f / 0.06
    buy7 = dps.to_f / 0.07
    m[:buy_price_5] = buy5
    m[:buy_price_6] = buy6
    m[:buy_price_7] = buy7
    m[:drop_to_5] = (1.0 - (buy5 / price.to_f)) * 100.0
    m[:drop_to_6] = (1.0 - (buy6 / price.to_f)) * 100.0
    m[:drop_to_7] = (1.0 - (buy7 / price.to_f)) * 100.0
  end
end

upcoming = []
codes = stocks.map { |s| s[:code] }
start_date = Date.today
end_date = Date.today + 183
codes.each_slice(120) do |batch_codes|
  filter = "(SECURITY_CODE in (\"#{batch_codes.join('","')}\"))(EX_DIVIDEND_DATE>='#{start_date.strftime('%Y-%m-%d')}')(EX_DIVIDEND_DATE<='#{end_date.strftime('%Y-%m-%d')}')"
  resp = http_get_json('https://datacenter-web.eastmoney.com/api/data/v1/get', params: {
    reportName: 'RPT_SHAREBONUS_DET',
    columns: 'ALL',
    pageNumber: 1,
    pageSize: 2000,
    sortColumns: 'EX_DIVIDEND_DATE',
    sortTypes: 1,
    source: 'WEB',
    client: 'WEB',
    filter: filter
  }, headers: ua_headers, timeout: 20, open_timeout: 10)
  rows = resp&.dig('result', 'data')
  next unless rows.is_a?(Array) && rows.any?
  rows.each do |row|
    code = row['SECURITY_CODE'].to_s.strip.rjust(6, '0')
    ex_date = parse_date(row['EX_DIVIDEND_DATE'])
    next unless ex_date
    plan = row['IMPL_PLAN_PROFILE'].to_s.strip
    next if plan.empty?
    yield_pct = row['DIVIDENT_RATIO'].nil? ? nil : row['DIVIDENT_RATIO'].to_f * 100.0
    cash_per_share = parse_cash_dividend_per_share(plan)
    upcoming << {
      code: code,
      name: row['SECURITY_NAME_ABBR'].to_s.strip,
      ex_dividend_date: ex_date.to_s,
      equity_record_date: (parse_date(row['EQUITY_RECORD_DATE'])&.to_s),
      notice_date: (parse_date(row['NOTICE_DATE']) || parse_date(row['PLAN_NOTICE_DATE']) || parse_date(row['PUBLISH_DATE']))&.to_s,
      cash_dividend_per_share: cash_per_share,
      dividend_yield_pct: yield_pct,
      progress: row['ASSIGN_PROGRESS'].to_s.strip,
      plan_description: plan
    }
  end
  sleep(0.08)
end
upcoming.sort_by! { |x| [x[:ex_dividend_date].to_s, x[:code].to_s] }

rows_out =
  code_to_metrics.values
    .select { |x| x[:dividend_yield].to_f > 3.0 }
    .sort_by { |x| [-x[:buy_score].to_f, -(x[:dividend_yield] || 0).to_f, x[:code]] }

generated_at = Time.now.utc.iso8601

html = <<~HTML
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>GT3 红利列表</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;margin:0;padding:24px;background:#f7f7fb;color:#111}
    h1{margin:0 0 8px 0;font-size:20px}
    .meta{color:#666;font-size:12px;margin-bottom:16px}
    .card{background:#fff;border:1px solid #eee;border-radius:10px;padding:16px;margin-bottom:16px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
    table{border-collapse:collapse;width:100%;font-size:12px}
    th,td{border-bottom:1px solid #eee;padding:8px 10px;vertical-align:middle}
    th{position:sticky;top:0;background:#fff;cursor:pointer;user-select:none;white-space:nowrap}
    td{white-space:nowrap}
    .right{text-align:right}
    .muted{color:#888}
    .neg{color:#0a7}
    .pos{color:#c33}
    .search{width:280px;max-width:100%;padding:8px 10px;border:1px solid #ddd;border-radius:8px;font-size:12px}
    .row-hidden{display:none}
  </style>
</head>
<body>
  <div class="card">
    <h1>GT3 红利列表（股息率&gt;3%）</h1>
    <div class="meta">生成时间(UTC)：#{generated_at} · 行数：#{rows_out.size}</div>
    <input id="q" class="search" placeholder="搜索 名称/代码" />
  </div>

  <div class="card">
    <table id="t">
      <thead>
        <tr>
          <th data-k="name" data-t="str">名称</th>
          <th data-k="code" data-t="str">代码</th>
          <th class="right" data-k="score" data-t="num">评分</th>
          <th class="right" data-k="avg3y" data-t="num">3年均息率</th>
          <th class="right" data-k="dy" data-t="num">股息率</th>
          <th class="right" data-k="drop5" data-t="num">5%需跌</th>
          <th class="right" data-k="drop6" data-t="num">6%需跌</th>
          <th class="right" data-k="drop7" data-t="num">7%需跌</th>
          <th class="right" data-k="pepct" data-t="num">PE分位</th>
          <th class="right" data-k="pbpct" data-t="num">PB分位</th>
          <th class="right" data-k="pos" data-t="num">价格分位</th>
          <th class="right" data-k="roe" data-t="num">ROE</th>
          <th class="right" data-k="debt" data-t="num">资产负债率</th>
          <th class="right" data-k="fcf" data-t="num">FCF收益率</th>
        </tr>
      </thead>
      <tbody>
HTML

rows_out.each do |r|
  html << "<tr>"
  html << "<td data-v=\"#{r[:name]}\">#{r[:name]}</td>"
  html << "<td data-v=\"#{r[:code]}\">#{r[:code]}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:buy_score]}\">#{format_score_half(r[:buy_score])}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:avg_dividend_yield_3y]}\">#{format_pct(r[:avg_dividend_yield_3y], 2)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:dividend_yield]}\">#{format_pct(r[:dividend_yield], 2)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:drop_to_5]}\">#{format_pct(r[:drop_to_5], 1)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:drop_to_6]}\">#{format_pct(r[:drop_to_6], 1)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:drop_to_7]}\">#{format_pct(r[:drop_to_7], 1)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:pe_percentile]}\">#{format_ratio_pct(r[:pe_percentile], 0)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:pb_percentile]}\">#{format_ratio_pct(r[:pb_percentile], 0)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:price_position]}\">#{format_ratio_pct(r[:price_position], 0)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:roe_jq]}\">#{format_pct(r[:roe_jq], 1)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:asset_liability_ratio]}\">#{format_pct(r[:asset_liability_ratio], 1)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:fcf_yield]}\">#{format_pct(r[:fcf_yield], 2)}</td>"
  html << "</tr>\n"
end

html << <<~HTML
      </tbody>
    </table>
  </div>

  <div class="card">
    <h1 style="font-size:16px;margin:0 0 8px 0;">半年内即将分红</h1>
    <div class="meta">按除权除息日正序 · 条数：#{upcoming.size}</div>
    <table id="t2">
      <thead>
        <tr>
          <th data-k="ex" data-t="str">除权除息日</th>
          <th data-k="name" data-t="str">股票</th>
          <th data-k="code" data-t="str">代码</th>
          <th class="right" data-k="cash" data-t="num">每股派现</th>
          <th class="right" data-k="y" data-t="num">股息率</th>
          <th data-k="p" data-t="str">进度</th>
          <th data-k="plan" data-t="str">方案</th>
        </tr>
      </thead>
      <tbody>
HTML

upcoming.each do |d|
  html << "<tr>"
  html << "<td data-v=\"#{d[:ex_dividend_date]}\">#{d[:ex_dividend_date]}</td>"
  html << "<td data-v=\"#{d[:name]}\">#{d[:name]}</td>"
  html << "<td data-v=\"#{d[:code]}\">#{d[:code]}</td>"
  html << "<td class=\"right\" data-v=\"#{d[:cash_dividend_per_share]}\">#{format_num(d[:cash_dividend_per_share], 4)}</td>"
  html << "<td class=\"right\" data-v=\"#{d[:dividend_yield_pct]}\">#{format_pct(d[:dividend_yield_pct], 2)}</td>"
  html << "<td data-v=\"#{d[:progress]}\">#{d[:progress]}</td>"
  html << "<td data-v=\"#{d[:plan_description]}\">#{d[:plan_description]}</td>"
  html << "</tr>\n"
end

html << <<~HTML
      </tbody>
    </table>
  </div>

  <script>
    (function(){
      function getVal(td, type){
        const v = td.getAttribute('data-v');
        if(v===null||v==='') return null;
        if(type==='num'){
          const n = Number(v);
          return Number.isFinite(n) ? n : null;
        }
        return String(v);
      }
      function sortTable(table, key, type, dir){
        const tbody = table.querySelector('tbody');
        const rows = Array.from(tbody.querySelectorAll('tr'));
        const idx = Array.from(table.querySelectorAll('thead th')).findIndex(th => th.getAttribute('data-k')===key);
        rows.sort((a,b)=>{
          const av = getVal(a.children[idx], type);
          const bv = getVal(b.children[idx], type);
          if(av===null && bv===null) return 0;
          if(av===null) return 1;
          if(bv===null) return -1;
          if(type==='num') return av-bv;
          return av.localeCompare(bv,'zh');
        });
        if(dir==='desc') rows.reverse();
        rows.forEach(r=>tbody.appendChild(r));
      }
      function bind(table){
        const ths = table.querySelectorAll('thead th[data-k]');
        ths.forEach(th=>{
          th.addEventListener('click', ()=>{
            const key = th.getAttribute('data-k');
            const type = th.getAttribute('data-t') || 'str';
            const cur = th.getAttribute('data-dir') || '';
            const dir = cur==='asc' ? 'desc' : 'asc';
            ths.forEach(x=>x.removeAttribute('data-dir'));
            th.setAttribute('data-dir', dir);
            sortTable(table, key, type, dir);
          });
        });
      }
      const t = document.getElementById('t');
      const t2 = document.getElementById('t2');
      bind(t);
      bind(t2);
      sortTable(t, 'score', 'num', 'desc');

      const q = document.getElementById('q');
      const rows = Array.from(document.querySelectorAll('#t tbody tr'));
      q.addEventListener('input', ()=>{
        const s = q.value.trim().toLowerCase();
        rows.forEach(r=>{
          if(!s){ r.classList.remove('row-hidden'); return; }
          const name = r.children[0].textContent.trim().toLowerCase();
          const code = r.children[1].textContent.trim().toLowerCase();
          if(name.includes(s) || code.includes(s)) r.classList.remove('row-hidden'); else r.classList.add('row-hidden');
        });
      });
    })();
  </script>
</body>
</html>
HTML

File.write(OUT_HTML, html)

payload = {
  generated_at_utc: generated_at,
  source_yml: File.basename(IN_YML),
  filter: { dividend_yield_gt: 3.0 },
  stocks: rows_out,
  upcoming_dividends_6m: upcoming
}
File.write(OUT_YML, payload.to_yaml)

puts "written #{OUT_HTML}"
puts "written #{OUT_YML}"
