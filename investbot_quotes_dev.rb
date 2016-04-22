#!/usr/local/bin/ruby

require 'httparty'
require 'nokogiri'
require 'sequel'
require 'json'
require 'yaml'
require 'logger'

$LOG = Logger.new('/var/log/investbot_quotes.log', 'monthly')

# read through config file to grab DB and API info
config = YAML.load_file("/opt/investbot/new_config.yml")

$db_user = config['db_user']
$db_pass = config['db_pass']
$db_host = config['db_host']
$db_name = config['db_name']

class StockExchange
  include HTTParty
  base_uri 'dev.markitondemand.com'

  def initialize
    @options = {}
  end

  def quote(stockname)
    self.class.get("/MODApis/Api/v2/Quote?symbol=#{stockname}")
  end

  def interactiveChart(parameters)
    self.class.get("/MODApis/Api/v2/InteractiveChart/json?parameters=#{parameters}")
  end

end

def getStockQuote(stock_symbol)
  begin
    begin
      stock_exchange = StockExchange.new
      stock_results = stock_exchange.quote(stock_symbol)
    end while stock_results.code != 200 && stock_results =! nil

    jsonresponse = stock_results.to_json
    stock_quote = JSON.parse(jsonresponse)["StockQuote"]
  rescue => error
    report_error("#{error.class}: #{error.message}")
  end
  return stock_quote
end

def report_error(error_message)
  (Thread.current[:errors] ||= []) << "#{error_message}"
end

def log_errors()
    (Thread.current[:errors] ||= []).each do |error|
      $LOG.error(error)
    end
end

def startProgram()
  begin
    # get connection to db - replace with connection to RDS
    db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

    # get a handle to table
    stock_price = db[:stock_price_dev]
    user_selections = db[:stock_selections_dev].select(:stock_symbol).distinct(:stock_symbol)

    user_selections.each { |row|
      stock_symbol = row[:stock_symbol]
      stock_quote = getStockQuote(stock_symbol)
      entry_time = Time.now
      stock_price.insert(
        :stock_name => stock_quote["Name"],
        :stock_symbol => stock_quote["Symbol"],
        :timestamp => stock_quote["Timestamp"],
        :entry_time => entry_time,
        :stock_price => stock_quote["LastPrice"]
       )
    }
    db.disconnect
  rescue => error
    report_error("#{error.class}: #{error.message}")
  end
end

startProgram()
at_exit { log_errors }
