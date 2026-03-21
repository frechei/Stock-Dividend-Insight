class RecreateRollingPriceMetricsToStocks < ActiveRecord::Migration[8.1]
  def change
    # 先清理之前残留的字段（如果有）
    %i[
      month_high month_low month_position
      year_high year_low year_position
      high_1y low_1y position_1y
      high_3y low_3y position_3y
      high_5y low_5y position_5y
    ].each do |col|
      remove_column :stocks, col, :decimal if column_exists?(:stocks, col)
    end

    # 统一命名约定的新字段
    # 30天滚动
    add_column :stocks, :high_30d, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :high_30d)
    add_column :stocks, :low_30d, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :low_30d)
    add_column :stocks, :pos_30d, :decimal, precision: 5, scale: 4 unless column_exists?(:stocks, :pos_30d)

    # 1年滚动
    # 注意：之前可能存在 high_1y, low_1y，如果已存在则跳过或重新定义
    add_column :stocks, :high_1y, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :high_1y)
    add_column :stocks, :low_1y, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :low_1y)
    add_column :stocks, :pos_1y, :decimal, precision: 5, scale: 4 unless column_exists?(:stocks, :pos_1y)

    # 3年滚动
    add_column :stocks, :high_3y, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :high_3y)
    add_column :stocks, :low_3y, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :low_3y)
    add_column :stocks, :pos_3y, :decimal, precision: 5, scale: 4 unless column_exists?(:stocks, :pos_3y)

    # 5年滚动
    add_column :stocks, :high_5y, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :high_5y)
    add_column :stocks, :low_5y, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :low_5y)
    add_column :stocks, :pos_5y, :decimal, precision: 5, scale: 4 unless column_exists?(:stocks, :pos_5y)
    
    # 确保 current_price 存在
    add_column :stocks, :current_price, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :current_price)
  end
end
