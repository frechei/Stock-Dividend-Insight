class AddDrop30dToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :drop_30d, :decimal, precision: 10, scale: 4 unless column_exists?(:stocks, :drop_30d)
    add_index :stocks, :drop_30d unless index_exists?(:stocks, :drop_30d)
  end
end
