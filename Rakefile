require 'active_record'
require 'dotenv/load'

# 数据库配置
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

desc "Run migrations"
task :migrate do
  ActiveRecord::MigrationContext.new('db/migrate').migrate
end

desc "Rollback migration"
task :rollback do
  ActiveRecord::MigrationContext.new('db/migrate').rollback
end

desc "Setup database (create and migrate)"
task :setup => [:create, :migrate]

task :create do
  require 'uri'
  uri = URI.parse(ENV['DATABASE_URL'])
  dbname = uri.path[1..-1]
  
  # 建立到 default 数据库的连接以创建新数据库
  ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'].gsub(dbname, 'postgres'))
  begin
    ActiveRecord::Base.connection.create_database(dbname)
    puts "Database '#{dbname}' created."
  rescue ActiveRecord::DatabaseAlreadyExists
    puts "Database '#{dbname}' already exists."
  end
  # 重新连回目标数据库
  ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
end
