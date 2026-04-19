class PriceMetricsCalculator
  def self.calculate(stock)
    # 获取数据库中最新的价格记录作为基准日期和收盘价
    latest_history = stock.price_histories.order(date: :desc).first
    return if latest_history.nil?

    base_price = stock.current_price && stock.current_price.to_f > 0 ? stock.current_price.to_f : latest_history.close
    base_date = latest_history.date

    # 1. 30天滚动 (月度)
    update_metrics(stock, "30d", 30, base_date, base_price)

    # 2. 1年滚动 (年度)
    update_metrics(stock, "1y", 365, base_date, base_price)

    # 3. 3年滚动
    update_metrics(stock, "3y", 1095, base_date, base_price)

    # 4. 5年滚动
    update_metrics(stock, "5y", 1825, base_date, base_price)

    stock.save! if stock.changed?
  end

  private

  def self.update_metrics(stock, suffix, days, base_date, base_price)
    start_date = base_date - days
    scope = stock.price_histories.where('date >= ? AND date <= ?', start_date, base_date)
    
    high = scope.maximum(:high)
    low = scope.minimum(:low)
    closes = scope.order(:date).where.not(close: nil).pluck(:close).map { |x| x.to_f }.select { |x| x.finite? && x > 0 }

    if high && low
      stock.send("high_#{suffix}=", high)
      stock.send("low_#{suffix}=", low)
    end

    if closes.any?
      stock.send("pos_#{suffix}=", percentile_for(base_price.to_f, closes))
      if suffix == '30d'
        start_close = closes.first
        stock.drop_30d = start_close && start_close > 0 ? ((start_close - base_price.to_f) / start_close.to_f) * 100.0 : nil
      end
    end
  end

  def self.percentile_for(current, arr)
    return nil if current.nil?
    c = current.to_f
    return nil unless c.finite? && c > 0

    values = Array(arr).map { |x| x.to_f }.select { |x| x.finite? && x > 0 }
    return nil if values.empty?
    return 0.5 if values.size <= 1

    sorted = values.sort
    idx = sorted.bsearch_index { |x| x >= c } || (sorted.size - 1)
    p = idx.to_f / (sorted.size - 1).to_f
    [[p, 0.0].max, 1.0].min
  end
end
