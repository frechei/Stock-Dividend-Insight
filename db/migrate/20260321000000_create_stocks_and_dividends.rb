class CreateStocksAndDividends < ActiveRecord::Migration[8.1]
  def change
    create_table :stocks do |t|
      t.string :name, null: false     # 股票名称 (e.g., 平安银行)
      t.string :secid, null: false    # 东方财富格式 ID (e.g., 0.000001)
      t.string :code, null: false     # 股票代码 (e.g., 000001)
      t.integer :market_id, null: false # 市场 ID (0: 深证, 1: 上证)
      t.decimal :dividend_yield, precision: 10, scale: 4 # 历史股息率 (%)
      t.decimal :expected_dividend_yield, precision: 10, scale: 4 # 预期股息率 (%)
      t.timestamps
    end
    add_index :stocks, :secid, unique: true
    add_index :stocks, :code

    create_table :price_histories do |t|
      t.references :stock, null: false, foreign_key: true # 关联股票 ID
      t.date :date, null: false                           # 交易日期
      t.decimal :open, precision: 15, scale: 4           # 开盘价
      t.decimal :close, precision: 15, scale: 4          # 收盘价
      t.decimal :high, precision: 15, scale: 4           # 最高价
      t.decimal :low, precision: 15, scale: 4            # 最低价
      t.bigint :volume                                   # 成交量 (手)
      t.decimal :amount, precision: 20, scale: 4         # 成交额
      t.decimal :amplitude, precision: 10, scale: 4      # 振幅
      t.timestamps
    end
    add_index :price_histories, [:stock_id, :date], unique: true

    create_table :dividends do |t|
      t.references :stock, null: false, foreign_key: true # 关联股票 ID
      t.date :report_date, null: false                    # 报告期 (e.g., 2023-12-31)
      t.date :notice_date                                 # 公告日期
      t.string :plan_description                          # 分红方案描述 (e.g., 10派1.60元)
      t.decimal :cash_dividend, precision: 15, scale: 4   # 每股派现 (元)
      t.decimal :bonus_issue, precision: 15, scale: 4     # 每股送股 (股)
      t.decimal :rights_issue, precision: 15, scale: 4    # 每股转增 (股)
      t.decimal :dividend_yield, precision: 10, scale: 4  # 股息率 (%)
      t.timestamps
    end
    add_index :dividends, [:stock_id, :report_date], unique: true
  end
end
