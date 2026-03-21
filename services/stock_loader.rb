require 'yaml'

class StockLoader
  def initialize(file_path = 'stocks.yml')
    @file_path = file_path
  end

  def load
    puts "Loading stocks from #{@file_path}..."
    stocks_data = YAML.load_file(@file_path)
    
    stocks_data.each do |data|
      next unless data['secid'] && data['name']
      
      market_id, code = data['secid'].split('.')
      
      Stock.find_or_create_by!(secid: data['secid']) do |s|
        s.name = data['name']
        s.market_id = market_id.to_i
        s.code = code
      end
    end
    puts "Loaded #{Stock.count} stocks."
  end
end
