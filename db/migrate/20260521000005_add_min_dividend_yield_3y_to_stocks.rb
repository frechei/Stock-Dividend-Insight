class AddMinDividendYield3yToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :min_dividend_yield_3y, :decimal, precision: 10, scale: 4 unless column_exists?(:stocks, :min_dividend_yield_3y)
    add_index :stocks, :min_dividend_yield_3y unless index_exists?(:stocks, :min_dividend_yield_3y)
  end
end
