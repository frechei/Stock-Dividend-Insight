class CreateStockNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_notes do |t|
      t.references :stock, null: false
      t.references :user, null: false
      t.text :body, null: false
      t.timestamps
    end

    add_index :stock_notes, [:stock_id, :created_at]
    add_index :stock_notes, [:user_id, :created_at]
  end
end
