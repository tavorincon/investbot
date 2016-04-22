#!/usr/local/bin/ruby

require 'httparty'
require 'nokogiri'
require 'sequel'
require 'json'
require 'yaml'
require 'twilio-ruby'
require 'logger'

$LOG = Logger.new('/var/log/investbot.log', 'monthly')

username = ARGV[0]
#stock_price_db = "stock_price"
#$stock_selections_db = {:db => "stock_selections"}

if ARGV.empty?
  puts "Usage: #{__FILE__} <username>"
  puts "At least one argument is required"
  exit(2)
end

# read through config file to grab DB and API info
config = YAML.load_file("/opt/investbot/new_config.yml")

$db_user = config['db_user']
$db_pass = config['db_pass']
$db_host = config['db_host']
$db_name = config['db_name']
$account_sid = config['account_sid']
$auth_token = config['auth_token']
$twillio_number = config['twillio_number']
bpl = config[username]['bpl']
bph = config[username]['bph']
spl = config[username]['spl']
sph = config[username]['sph']
delta_t = config[username]['delta_t']
phone_number = config[username]['number']

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
  
  begin  
    stock_exchange = StockExchange.new
    stock_results = stock_exchange.quote(stock_symbol)
  end while stock_results.code != 200

  jsonresponse = stock_results.to_json
  stock_quote = JSON.parse(jsonresponse)["StockQuote"]
  last_price = stock_quote["LastPrice"].to_f 
  return last_price
end

def getSMA(stock_symbol, daily_dps, days_sma)

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  total_dps = daily_dps * days_sma
  
  #avg = db[:stock_price].limit(total_dps).filter(:stock_symbol => stock_symbol).avg(:stock_price).to_f
  avg = db[:stock_price].reverse_order(:entry_time).limit(total_dps).filter(:stock_symbol => stock_symbol).avg(:stock_price).to_f
  #puts "This is the result of getSMA() #{avg}"
  db.disconnect
  return avg

end

def buyStock(stock_symbol, username, phone_number, bpl, bph, delta_t)

  $LOG.info("Buying Stock: #{stock_symbol}, Username: #{username}")

  begin
    current_price = getCurrentPrice(stock_symbol)
    sma = getSMA(stock_symbol, 390, 5)

    buy_high_thres = (sma * bph).round(2)
    buy_low_thres = (sma * bpl).round(2)
    delta_price_1 = getHistoricalPrice(stock_symbol,(1*delta_t))
    delta_price_2 = getHistoricalPrice(stock_symbol,(2*delta_t))
    delta_price_3 = getHistoricalPrice(stock_symbol,(3*delta_t))

    if delta_price_1.nil? || delta_price_2.nil? || delta_price_3.nil?
      #puts "don't buy now"
      $LOG.info("Stock buy order did not have enough delta data points for #{stock_symbol}, Username: #{username}")
    else
      slope_1 = (current_price - delta_price_1) / (1*delta_t)
      slope_2 = (current_price - delta_price_2) / (2*delta_t)
      slope_3 = (current_price - delta_price_3) / (3*delta_t)
      
      $LOG.debug("Stock buy condition parameters for #{stock_symbol} are SMA: #{sma.round(2)}, Current Price: #{current_price}, Low Thres: #{buy_low_thres}, Buy High Thres: #{buy_high_thres}, Slope 1: #{slope_1}, Slope 2: #{slope_2}, Slope 3: #{slope_3}")

      db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

      if buy_low_thres < current_price && current_price < buy_high_thres && slope_1 > 0 && slope_2 > 0 && slope_3 > 0
        #puts "Buy #{stock_symbol} now!"
        user_selections = db[:stock_selections]
        stock_orders = db[:stock_orders]
        user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:own_stock => true)
        user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:buy_price => current_price)
        entry_time = Time.now
        stock_orders.insert(:stock_symbol => stock_symbol, :stock_owner => username, :order_type => "buy", :stock_price => current_price, :timestamp => entry_time, :bpl => bpl, :bph => bph, :delta_time => delta_t)
        sendNotification(phone_number, "Buy #{stock_symbol} between $#{buy_low_thres} and $#{buy_high_thres}")
        $LOG.info("Stock buy order successful: #{stock_symbol}, Username: #{username}, Price: #{current_price}")
      else
        #puts "don't buy now"
        $LOG.info("Stock buy order did not meet conditions for #{stock_symbol}, Username: #{username}")
      end
      db.disconnect
    end
  rescue Exception => e
    $LOG.error "Error in buyStock execution!: #{e}"
  end
end

def sellStock(stock_symbol, username, phone_number, spl, sph, delta_t)

  $LOG.info("Selling Stock: #{stock_symbol}, Username: #{username}")

  begin
    # get connection to db - replace with connection to RDS
    db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

    current_price = getCurrentPrice(stock_symbol)
    buy_price = db[:stock_selections].select(:buy_price).where(:stock_owner => username, :stock_symbol => stock_symbol).first[:buy_price].to_f

    sell_high_thres = (buy_price * sph).round(2)
    sell_low_thres = (buy_price * spl).round(2)
    delta_price_1 = getHistoricalPrice(stock_symbol,1*delta_t)
    delta_price_2 = getHistoricalPrice(stock_symbol,2*delta_t)
    delta_price_3 = getHistoricalPrice(stock_symbol,3*delta_t)

    if delta_price_1.nil? || delta_price_2.nil? || delta_price_3.nil?
      #puts "don't sell now"
      $LOG.info("Stock sell order did not have enough delta data points for #{stock_symbol}, Username: #{username}")
    else
      slope_1 = (current_price - delta_price_1) / (1*delta_t)
      slope_2 = (current_price - delta_price_2) / (2*delta_t)
      slope_3 = (current_price - delta_price_3) / (3*delta_t)

      $LOG.debug("Stock sell condition parameters for #{stock_symbol} are: Buy Price: #{buy_price}, Current Price: #{current_price}, Low Thres: #{sell_low_thres}, Sell High Thres: #{sell_high_thres}, Slope 1: #{slope_1}, Slope 2: #{slope_2}, Slope 3: #{slope_3}")

      if current_price > sell_high_thres && slope_1 < 0 && slope_2 < 0 && slope_3 < 0
        user_selections = db[:stock_selections]
        user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:own_stock => false)
        entry_time = Time.now
        stock_orders = db[:stock_orders]
        stock_orders.insert(:stock_symbol => stock_symbol, :stock_owner => username, :order_type => "sell", :stock_price => current_price, :timestamp => entry_time, :spl => spl, :sph => sph, :delta_time => delta_t)
        sendNotification(phone_number, "WIN! Sell #{stock_symbol} before price goes below $#{sell_high_thres}")
        $LOG.info("Stock sell order successful: #{stock_symbol}, Username: #{username}, Price: #{current_price}")
      elsif current_price < sell_low_thres
        user_selections = db[:stock_selections]
        user_selections.where(:stock_owner => username, :stock_symbol => stock_symbol).update(:own_stock => false)
        entry_time = Time.now
        stock_orders = db[:stock_orders]
        stock_orders.insert(:stock_symbol => stock_symbol, :stock_owner => username, :order_type => "sell", :stock_price => current_price, :timestamp => entry_time, :spl => spl, :sph => sph, :delta_time => delta_t)
        sendNotification(phone_number, "LOSS! Sell #{stock_symbol} before price goes below $#{sell_low_thres}")
        $LOG.info("Stock sell order successful: #{stock_symbol}, Username: #{username}, Price: #{current_price}")
      else
        #puts "Don't sell"
        $LOG.info("Stock sell order did not meet conditions for #{stock_symbol}, Username: #{username}")
      end 
      db.disconnect
    end
  rescue Exception => e
    $LOG.error "Error in sellStock execution!: #{e}"
  end
end

def getHistoricalPrice(stock_symbol,delta_time)

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  historical_price = db[:stock_price].select(:stock_price).reverse_order(:entry_time).where(:stock_symbol => stock_symbol)
  
  if historical_price.any? 
    delta = historical_price.first(delta_time)
    hist_price = delta.last[:stock_price].to_f
    #puts "This is the result of getHistoricalPrice() #{hist_price}"
    db.disconnect
    return hist_price
  end

end 

def sendNotification(phone_number, message)

  # set up a client to talk to the Twilio REST API 
  @client = Twilio::REST::Client.new $account_sid, $auth_token 
 
  @client.account.messages.create({
    :from => $twillio_number,
    :to => phone_number, 
    :body => message, 
  })
end

def startProgram(username,phone_number,bpl,bph,spl,sph,delta_t)

  $LOG.info("Starting Investbot Engine execution for: #{username}")

  # get connection to db - replace with connection to RDS
  db = Sequel.connect(:adapter => 'mysql2', :user => $db_user, :host => $db_host, :database => $db_name, :password => $db_pass)

  user_selections = db[:stock_selections].select(:stock_symbol, :own_stock).where(:stock_owner => username)

  user_selections.each { |row|
    stock_ownership = row[:own_stock]
    if stock_ownership
      sellStock(row[:stock_symbol], username, phone_number, spl, sph, delta_t)
    else 
      buyStock(row[:stock_symbol], username, phone_number, bpl, bph, delta_t)
    end
    db.disconnect
    #sleep(3)
  }
  $LOG.info("Ending Investbot Engine execution for: #{username}")
end

# Program Execution
startProgram(username,phone_number,bpl,bph,spl,sph,delta_t)
