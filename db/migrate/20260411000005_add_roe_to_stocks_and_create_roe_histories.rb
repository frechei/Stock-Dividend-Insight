class AddRoeToStocksAndCreateRoeHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :roe_jq, :decimal, precision: 6, scale: 2
    add_column :stocks, :roe_kc_jq, :decimal, precision: 6, scale: 2
    add_column :stocks, :roe_report_date, :date
    add_column :stocks, :roe_report_type, :string
    add_index :stocks, :roe_report_date

    create_table :roe_histories do |t|
      t.references :stock, null: false
      t.date :report_date, null: false
      t.string :report_type
      t.string :report_year
      t.decimal :roe_jq, precision: 6, scale: 2
      t.decimal :roe_kc_jq, precision: 6, scale: 2
      t.date :notice_date
      t.date :update_date
      t.timestamps
    end

    add_index :roe_histories, [:stock_id, :report_date], unique: true
  end
end
