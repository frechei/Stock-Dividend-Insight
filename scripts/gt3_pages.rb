require 'yaml'
require 'date'
require 'time'
require 'fileutils'

ROOT_DIR = File.expand_path('..', __dir__)
IN_YML = File.join(ROOT_DIR, 'stocks-dividend-gt3.yml')
OUT_DIR = File.join(ROOT_DIR, 'docs', 'gt3')
OUT_HTML = File.join(OUT_DIR, 'index.html')
OUT_YML = File.join(OUT_DIR, 'data.yml')

require_relative '../models'

FileUtils.mkdir_p(OUT_DIR)

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

raise "missing #{IN_YML}" unless File.exist?(IN_YML)
data = YAML.load_file(IN_YML)
list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])
yml_rows =
  list.filter_map do |row|
    code = row['code'].to_s.strip.rjust(6, '0')
    next unless code.match?(/^\d{6}$/)
    name = row['name'].to_s.strip
    next if name.empty?
    { code: code, name: name, categories: Array(row['categories']).map(&:to_s) }
  end

codes = yml_rows.map { |x| x[:code] }.uniq

stocks =
  Stock
    .where(asset_type: 'stock', code: codes)
    .pluck(
      :id, :code, :name,
      :buy_score, :avg_dividend_yield_3y, :dividend_yield,
      :dividend_cash_per_share_latest_year, :current_price,
      :pe_percentile, :pb_percentile, :price_position,
      :roe_jq, :drop_30d, :asset_liability_ratio, :fcf_yield
    )
    .map do |id, code, name, buy_score, avg3y, dy, dps, price, pe_pct, pb_pct, pos, roe, drop30, debt, fcf_y|
      {
        id: id,
        code: code.to_s.rjust(6, '0'),
        name: name.to_s,
        buy_score: buy_score&.to_f,
        avg_dividend_yield_3y: avg3y&.to_f,
        dividend_yield: dy&.to_f,
        dividend_cash_per_share_latest_year: dps&.to_f,
        current_price: price&.to_f,
        pe_percentile: pe_pct&.to_f,
        pb_percentile: pb_pct&.to_f,
        price_position: pos&.to_f,
        roe_jq: roe&.to_f,
        drop_30d: drop30&.to_f,
        asset_liability_ratio: debt&.to_f,
        fcf_yield: fcf_y&.to_f
      }
    end

by_code = stocks.index_by { |x| x[:code] }

rows_out =
  yml_rows
    .filter_map do |row|
      m = by_code[row[:code]]
      next unless m
      dy = m[:dividend_yield]
      next unless dy && dy > 3.0

      dps = m[:dividend_cash_per_share_latest_year]
      price = m[:current_price]
      buy5 = (dps && dps > 0) ? (dps / 0.05) : nil
      buy6 = (dps && dps > 0) ? (dps / 0.06) : nil
      buy7 = (dps && dps > 0) ? (dps / 0.07) : nil
      drop5 = (buy5 && price && price > 0) ? ((1.0 - (buy5 / price)) * 100.0) : nil
      drop6 = (buy6 && price && price > 0) ? ((1.0 - (buy6 / price)) * 100.0) : nil
      drop7 = (buy7 && price && price > 0) ? ((1.0 - (buy7 / price)) * 100.0) : nil

      row.merge(m).merge(
        buy_price_5: buy5,
        buy_price_6: buy6,
        buy_price_7: buy7,
        drop_to_5: drop5,
        drop_to_6: drop6,
        drop_to_7: drop7
      )
    end

rows_out.sort_by! do |x|
  [-(x[:buy_score] || 0).to_f, -(x[:dividend_yield] || 0).to_f, x[:code]]
end

stock_ids = rows_out.map { |x| x[:id] }.uniq
start_date = Date.today
end_date = Date.today + 183
upcoming =
  FutureDividend
    .includes(:stock)
    .where(stock_id: stock_ids)
    .where(ex_dividend_date: start_date..end_date)
    .order(ex_dividend_date: :asc, security_code: :asc)
    .limit(1000)
    .map do |fd|
      {
        code: (fd.security_code.to_s.strip.empty? ? fd.stock&.code.to_s : fd.security_code.to_s).rjust(6, '0'),
        name: fd.security_name.to_s.strip.empty? ? fd.stock&.name.to_s : fd.security_name.to_s,
        ex_dividend_date: fd.ex_dividend_date&.to_s,
        equity_record_date: fd.equity_record_date&.to_s,
        notice_date: fd.notice_date&.to_s,
        cash_dividend_per_share: fd.cash_dividend_per_share&.to_f,
        dividend_yield_pct: fd.dividend_yield_pct&.to_f,
        progress: fd.progress.to_s,
        plan_description: fd.plan_description.to_s
      }
    end

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
          <th class="right" data-k="drop30" data-t="num">30天跌幅</th>
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
  html << "<td class=\"right\" data-v=\"#{r[:drop_30d]}\">#{format_pct(r[:drop_30d], 1)}</td>"
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
  stocks: rows_out.map { |x| x.reject { |k, _| k == :id } },
  upcoming_dividends_6m: upcoming
}
File.write(OUT_YML, payload.to_yaml)

puts "written #{OUT_HTML}"
puts "written #{OUT_YML}"
