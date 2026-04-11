class AddHasDividend5yToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :has_dividend_5y, :boolean, null: false, default: false
    add_index :stocks, :has_dividend_5y
  end
end

