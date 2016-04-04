#!/usr/local/bin/ruby

require 'httparty'
require 'nokogiri'
require 'sequel'
require 'json'
require 'yaml'
require 'twilio-ruby'
require 'optparse'

username = ARGV

# read through config file to grab DB and API info
config = YAML.load_file("config.yml")

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

  def quote(stock_symbol)
    self.class.get("/MODApis/Api/v2/Quote?symbol=#{stock_symbol}")
  end

  def interactiveChart(parameters)
    self.class.get("/MODApis/Api/v2/InteractiveChart/json?parameters=#{parameters}")
  end

end

def getCurrentPrice(stock_symbol)
  
  stock_exchange = StockExchange.new
  stock_results = stock_exchange.quote(stock_symbol)

  jsonresponse = stock_results.to_json
  # puts jsonresponse
  if stock_results.code != 200
   raise "failed to query"
  else
  # util.truncate
   current_price = JSON.parse(jsonresponse)["StockQuote"]
  end
  last_price = current_price["LastPrice"].to_f
  #puts "This is the result of getCurrentPrice(): #{last_price}"
  return last_price
end

def getStockInfo(stock_symbol)

  stock_exchange = StockExchange.new
  stock_results = stock_exchange.quote(stock_symbol)

  jsonresponse = stock_results.to_json
  # puts jsonresponse
  if stock_results.code != 200
   raise "failed to query"
  else
  # util.truncate
   current_price = JSON.parse(jsonresponse)["StockQuote"]
  end
  return current_price
end

def getSMA(stock_symbol, daily_dps, days_sma)

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  total_dps = daily_dps * days_sma
  
  avg = db[:stock_price].limit(total_dps).filter(:stock_symbol => stock_symbol).avg(:stock_price).to_f
  #puts "This is the result of getSMA() #{avg}"
  db.disconnect
  return avg

end

def buyStock(stock_symbol, username, bpl, bph)

  current_price = getCurrentPrice(stock_symbol)
  sma = getSMA(stock_symbol, 390, 5)

  buy_high_thres = sma * bph
  buy_low_thres = sma * bpl
  delta_price_1 = getHistoricalPrice(stock_symbol,1)
  delta_price_2 = getHistoricalPrice(stock_symbol,2)
  delta_price_3 = getHistoricalPrice(stock_symbol,3)
  slope_1 = (current_price - delta_price_1) / 1
  slope_2 = (current_price - delta_price_2) / 2
  slope_3 = (current_price - delta_price_3) / 3

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  if buy_low_thres < current_price && current_price < buy_high_thres && slope_1 > 0 && slope_2 > 0 && slope_3 > 0
    puts "Buy #{stock_symbol} now!"
    user_selections = db[:stock_selections]
    user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:own_stock => true)
    sendNotification("+17542452512", stock_symbol, buy_high_thres)
  else
    puts "don't buy now"
  end
  db.disconnect
end

def sellStock(stock_symbol, username, spl, sph)

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  current_price = getCurrentPrice(stock_symbol)
  buy_price = db[:stock_selections].select(:buy_price).where(:stock_owner => username, :stock_symbol => stock_symbol).first[:buy_price].to_f

  sell_high_thres = buy_price * sph
  sell_low_thres = buy_price * spl
  delta_price_1 = getHistoricalPrice(stock_symbol,1)
  delta_price_2 = getHistoricalPrice(stock_symbol,2)
  delta_price_3 = getHistoricalPrice(stock_symbol,3)
  slope_1 = (current_price - delta_price_1) / 1
  slope_2 = (current_price - delta_price_2) / 2
  slope_3 = (current_price - delta_price_3) / 3

  if current_price > sell_high_thres && slope_1 < 0 && slope_2 < 0 && slope_3 < 0
    puts "Sell stock"
    user_selections = db[:stock_selections]
    user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:own_stock => false)
  elsif current_price < sell_low_thres
    puts "Sell stock"
    user_selections = db[:stock_selections]
    user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:own_stock => false)
  else
    puts "Don't sell"
  end 
  db.disconnect
end

def getHistoricalPrice(stock_symbol,delta_time)

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  historical_price = db[:stock_price].select(:stock_price).reverse_order(:entry_time).where(:stock_symbol => stock_symbol)

  delta = historical_price.first(delta_time)
  hist_price = delta.last[:stock_price].to_f
  #puts "This is the result of getHistoricalPrice() #{hist_price}"
  db.disconnect
  return hist_price

end 

def sendNotification(phone_number, stock_symbol, message)

  # read through config file to grab DB and API info
  config = YAML.load_file("config.yml")

  account_sid = config['account_sid']
  auth_token = config['auth_token']

  # set up a client to talk to the Twilio REST API 
  @client = Twilio::REST::Client.new account_sid, auth_token 
 
  @client.account.messages.create({
    :from => '+19546422747', 
    :to => phone_number, 
    :body => "#{message} #{stock_symbol}", 
  })
end

def startProgram(username)

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  user_selections = db[:stock_selections].select(:stock_symbol, :own_stock).where(:stock_owner => username)
  util = db[:stock_price_dev]

  user_selections.each { |row|
    returned_value = getStockInfo(row[:stock_symbol])
    stock_ownership = row[:own_stock]
    puts "this is the returned value from user selections #{returned_value} and own_stock is #{stock_ownership}"
    entry_time = Time.now
     util.insert(
       :stock_name => returned_value["Name"],
       :stock_symbol => returned_value["Symbol"],
       :timestamp => returned_value["Timestamp"],
       :entry_time => entry_time,
       :stock_price => returned_value["LastPrice"]
     )
    sleep(3)
    if stock_ownership
      sellStock(row[:stock_symbol], username, 0.995, 1.005)
    else 
      buyStock(row[:stock_symbol], username, 0.995, 0.998)
    end
  db.disconnect
  }
end

# Program Execution
if ARGV.empty?
  puts "Usage: #{__FILE__} <username>"
  puts "At least one argument is required"
  exit(2)
else
  startProgram(username)
end
