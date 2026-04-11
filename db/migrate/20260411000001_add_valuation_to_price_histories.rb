class AddValuationToPriceHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :price_histories, :pe_ttm, :decimal, precision: 10, scale: 4
    add_column :price_histories, :pb, :decimal, precision: 10, scale: 4
    add_index :price_histories, :pb
    add_index :price_histories, :pe_ttm
  end
end

