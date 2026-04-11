require 'sinatra'
require 'sinatra/reloader' if development?
require_relative 'models'
require_relative 'services/valuation_history_syncer'

set :bind, '0.0.0.0'
set :port, 4567

get '/' do
  allowed_sort_fields = %w[
    name code current_price expected_dividend_yield dividend_yield
    turnover_rate market_cap volume avg_price pe_ttm pb total_shares
    pos_30d pos_1y pos_3y pos_5y price_position
  ]
  
  category_id = params[:category_id]
  only_div5y = params[:only_div5y].to_s == '1'
  default_sorts = [{ field: 'expected_dividend_yield', order: 'desc' }]
  sorts = parse_sorts_param(params[:sort], default_sorts, allowed_sort_fields)
  if (remove_sort = params[:remove_sort].to_s.strip).size > 0
    sorts = sorts.reject { |s| s[:field] == remove_sort }
    sorts = default_sorts if sorts.empty?
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:category_id] = category_id if category_id && !category_id.to_s.empty?
    query_params[:only_div5y] = '1' if only_div5y
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end
  if params[:clear_sorts].to_s == '1'
    sorts = default_sorts
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:category_id] = category_id if category_id && !category_id.to_s.empty?
    query_params[:only_div5y] = '1' if only_div5y
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  base_scope = Stock.includes(:categories)
  if only_div5y
    base_scope = base_scope.where(has_dividend_5y: true)
  end
  sorts.each do |s|
    if s[:field] == 'pe_ttm' && s[:order] == 'asc'
      base_scope = base_scope.where('pe_ttm > 0')
    end
  end

  order_sql = sorts.map { |s| "#{s[:field]} #{s[:order]} NULLS LAST" }.join(', ')
  @stocks = base_scope.order(order_sql)
  
  if category_id && !category_id.to_s.empty?
    @stocks = @stocks.joins(:categorizations).where(categorizations: { category_id: category_id })
    @current_category = Category.find(category_id)
  end

  @categories = Category.joins(:categorizations).group('categories.id').order('count(categorizations.id) desc')
  @sorts = sorts
  @sort_param = serialize_sorts_param(sorts)
  @only_div5y = only_div5y
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :index
end

get '/macro' do
  @cn_10y_latest = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  @cn_10y_series = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :asc).pluck(:date, :yield_pct)
  erb :macro
end

get '/stocks/:id' do
  @stock = Stock.includes(:categories).find(params[:id])
  need_val = @stock.price_histories.where('date > ?', Date.today - 90).where(pb: nil).exists?
  if need_val
    ValuationHistorySyncer.new(scope: Stock.where(id: @stock.id), years: 10, sleep_range: nil).sync
  end
  # 价格走势（取最近 10 年），按日期升序用于绘图
  @price_histories = @stock.price_histories.order(date: :asc)
  # 分红历史，按报告期降序展示
  @dividends = @stock.dividends.order(report_date: :desc)
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :show
end

helpers do
  def parse_sorts_param(raw, default_sorts, allowed_fields)
    tokens = raw.to_s.split(',').map(&:strip).reject(&:empty?)
    return default_sorts if tokens.empty?

    out = []
    tokens.each do |tok|
      field, order = tok.split(':', 2)
      next unless allowed_fields.include?(field)
      order = order.to_s.downcase
      order = 'desc' unless %w[asc desc].include?(order)
      next if out.any? { |x| x[:field] == field }
      out << { field: field, order: order }
    end

    out.empty? ? default_sorts : out
  end

  def serialize_sorts_param(sorts)
    Array(sorts).map { |s| "#{s[:field]}:#{s[:order]}" }.join(',')
  end

  def build_query(params_hash)
    Rack::Utils.build_query(params_hash.reject { |_, v| v.nil? || v.to_s.empty? })
  end

  def sort_label(field)
    {
      'name' => '股票名称',
      'code' => '代码',
      'current_price' => '最新价',
      'expected_dividend_yield' => '预期股息率',
      'dividend_yield' => '历史股息率',
      'turnover_rate' => '换手率',
      'market_cap' => '总市值',
      'volume' => '成交量',
      'avg_price' => '均价',
      'pe_ttm' => 'PE(TTM)',
      'pb' => 'PB',
      'total_shares' => '总股本',
      'pos_30d' => '30d位置',
      'pos_1y' => '1y位置',
      'pos_3y' => '3y位置',
      'pos_5y' => '5y位置',
      'price_position' => '全量位置'
    }[field] || field
  end

  def format_decimal(value, precision = 2)
    return '-' if value.nil?
    sprintf("%.#{precision}f", value)
  end

  def format_percent(value)
    return '-' if value.nil?
    "#{format_decimal(value, 2)}%"
  end

  def format_market_cap(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f / 100_000_000.0, 1)}亿"
  end

  def format_volume(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f / 10_000.0, 2)}万手"
  end

  def format_shares(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f / 100_000_000.0, 2)}亿股"
  end

  def position_color(pos)
    return 'text-gray-400' if pos.nil?
    if pos < 0.2
      'text-green-600 font-bold'
    elsif pos < 0.4
      'text-green-500'
    elsif pos < 0.6
      'text-yellow-600'
    elsif pos < 0.8
      'text-red-500'
    else
      'text-red-700 font-bold'
    end
  end

  def sort_link(field, label)
    current = Array(@sorts)
    existing = current.find { |s| s[:field] == field }
    new_order = existing && existing[:order] == 'desc' ? 'asc' : 'desc'
    next_sorts = current.reject { |s| s[:field] == field }
    next_sorts.unshift({ field: field, order: new_order })

    icon = ''
    if existing
      idx = current.index(existing) + 1
      arrow = existing[:order] == 'desc' ? '↓' : '↑'
      icon = " #{idx}#{arrow}"
    end

    query_params = { sort: serialize_sorts_param(next_sorts) }
    query_params[:category_id] = params[:category_id] if params[:category_id] && !params[:category_id].to_s.empty?
    query_params[:only_div5y] = '1' if params[:only_div5y].to_s == '1'

    "<a href='?#{build_query(query_params)}' class='hover:underline text-blue-600'>#{label}#{icon}</a>"
  end
end
