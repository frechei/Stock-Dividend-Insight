class CreateFutureDividends < ActiveRecord::Migration[8.1]
  def change
    create_table :future_dividends do |t|
      t.string :unique_key, null: false
      t.bigint :stock_id, null: false
      t.string :security_code
      t.string :security_name
      t.date :ex_dividend_date, null: false
      t.date :equity_record_date
      t.date :notice_date
      t.string :progress
      t.text :plan_description
      t.decimal :dividend_yield_pct, precision: 10, scale: 4
      t.decimal :cash_dividend_per_share, precision: 12, scale: 4
      t.timestamps
    end

    add_index :future_dividends, :unique_key, unique: true
    add_index :future_dividends, :stock_id
    add_index :future_dividends, :ex_dividend_date
    add_index :future_dividends, :dividend_yield_pct
  end
end
