class AddFinancialFieldsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :finance_report_date, :date
    add_column :stocks, :revenue_yoy, :decimal, precision: 10, scale: 4
    add_column :stocks, :net_profit_yoy, :decimal, precision: 10, scale: 4
    add_column :stocks, :net_profit_yoy_deducted, :decimal, precision: 10, scale: 4

    add_column :stocks, :total_assets, :bigint
    add_column :stocks, :total_liabilities, :bigint
    add_column :stocks, :asset_liability_ratio, :decimal, precision: 10, scale: 4
    add_column :stocks, :interest_debt_ratio, :decimal, precision: 10, scale: 4

    add_column :stocks, :peg, :decimal, precision: 10, scale: 4

    add_index :stocks, :peg unless index_exists?(:stocks, :peg)
    add_index :stocks, :asset_liability_ratio unless index_exists?(:stocks, :asset_liability_ratio)
    add_index :stocks, :interest_debt_ratio unless index_exists?(:stocks, :interest_debt_ratio)
    add_index :stocks, :net_profit_yoy unless index_exists?(:stocks, :net_profit_yoy)
    add_index :stocks, :finance_report_date unless index_exists?(:stocks, :finance_report_date)
  end
end
