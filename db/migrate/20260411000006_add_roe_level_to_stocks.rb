class AddRoeLevelToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :roe_level, :integer
    add_index :stocks, :roe_level

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE stocks
          SET roe_level =
            CASE
              WHEN roe_jq IS NULL THEN NULL
              WHEN roe_jq > 20 THEN 3
              WHEN roe_jq > 15 THEN 2
              ELSE 1
            END
        SQL
      end
    end
  end
end
