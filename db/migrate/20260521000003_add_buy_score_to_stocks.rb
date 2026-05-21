class AddBuyScoreToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :buy_score, :decimal, precision: 6, scale: 2 unless column_exists?(:stocks, :buy_score)
    add_index :stocks, :buy_score unless index_exists?(:stocks, :buy_score)
  end
end
