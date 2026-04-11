class AddPeLevelsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :pe_level, :integer
    add_column :stocks, :pe_percentile, :decimal, precision: 6, scale: 4
    add_column :stocks, :pe_percentile_level, :integer

    add_index :stocks, :pe_level
    add_index :stocks, :pe_percentile_level
  end
end

