require 'active_record'

# 股票信息模型
# 字段:
# - name: 股票名称
# - secid: 东方财富 ID (市场.代码)
# - code: 股票代码
# - market_id: 市场 ID (0:深证, 1:上证)
# - dividend_yield: 历史股息率 (根据最后一次完整年度分红计算)
# - expected_dividend_yield: 预期股息率 (基于最近 12 个月分红和最新股价)
class Stock < ActiveRecord::Base
  has_many :price_histories, dependent: :destroy
  has_many :dividends, dependent: :destroy
end

# 价格历史行情模型
# 字段:
# - stock_id: 关联股票 ID
# - date: 交易日期
# - open: 开盘价
# - close: 收盘价
# - high: 最高价
# - low: 最低价
# - volume: 成交量
class PriceHistory < ActiveRecord::Base
  belongs_to :stock
end

# 分红历史模型
# 字段:
# - stock_id: 关联股票 ID
# - report_date: 报告期
# - notice_date: 公告日期
# - plan_description: 分红方案描述
# - cash_dividend: 每股派现
# - bonus_issue: 每股送股
# - rights_issue: 每股转增
# - dividend_yield: 股息率
class Dividend < ActiveRecord::Base
  belongs_to :stock
end
