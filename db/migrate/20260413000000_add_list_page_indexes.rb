class AddListPageIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :categorizations, [:category_id, :stock_id] unless index_exists?(:categorizations, [:category_id, :stock_id])

    add_index :stocks, :expected_dividend_yield unless index_exists?(:stocks, :expected_dividend_yield)
    add_index :stocks, :dividend_yield unless index_exists?(:stocks, :dividend_yield)

    add_index :stocks, :pe_ttm unless index_exists?(:stocks, :pe_ttm)
    add_index :stocks, :pe_percentile unless index_exists?(:stocks, :pe_percentile)

    add_index :stocks, :pb unless index_exists?(:stocks, :pb)
    add_index :stocks, :pb_percentile unless index_exists?(:stocks, :pb_percentile)

    add_index :stocks, :roe_jq unless index_exists?(:stocks, :roe_jq)

    add_index :stocks, :turnover_rate unless index_exists?(:stocks, :turnover_rate)
    add_index :stocks, :market_cap unless index_exists?(:stocks, :market_cap)
    add_index :stocks, :volume unless index_exists?(:stocks, :volume)
    add_index :stocks, :total_shares unless index_exists?(:stocks, :total_shares)

    add_index :stocks, :pos_30d unless index_exists?(:stocks, :pos_30d)
    add_index :stocks, :pos_1y unless index_exists?(:stocks, :pos_1y)
    add_index :stocks, :pos_3y unless index_exists?(:stocks, :pos_3y)
    add_index :stocks, :pos_5y unless index_exists?(:stocks, :pos_5y)
    add_index :stocks, :price_position unless index_exists?(:stocks, :price_position)
  end
end
