class AddRoe5yFlagsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :roe_5y_avg_ge_12, :boolean, default: false, null: false
    add_column :stocks, :roe_5y_min_ge_8, :boolean, default: false, null: false
    add_index :stocks, :roe_5y_avg_ge_12
    add_index :stocks, :roe_5y_min_ge_8
  end
end
