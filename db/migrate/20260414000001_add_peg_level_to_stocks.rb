class AddPegLevelToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :peg_level, :integer
    add_index :stocks, :peg_level unless index_exists?(:stocks, :peg_level)
  end
end
