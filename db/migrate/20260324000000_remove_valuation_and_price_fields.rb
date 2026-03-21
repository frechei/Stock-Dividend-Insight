class RemoveValuationAndPriceFields < ActiveRecord::Migration[8.1]
  def change
    # 从 stocks 表移除字段
    remove_column :stocks, :pe, :decimal
    remove_column :stocks, :pb, :decimal
    remove_column :stocks, :pe_position, :decimal
    remove_column :stocks, :pb_position, :decimal
    
    # 从 price_histories 表移除字段
    remove_column :price_histories, :pe, :decimal
    remove_column :price_histories, :pb, :decimal
    remove_column :price_histories, :amount, :decimal
    remove_column :price_histories, :amplitude, :decimal
  end
end
