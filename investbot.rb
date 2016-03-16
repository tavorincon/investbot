#!/usr/local/bin/ruby

require 'httparty'
require 'nokogiri'
require 'sequel'
require 'json'
require 'yaml'

#puts util

# GET data from API


def getCurrentPrice(stockname)

  #headers = { "Authorization" => "Basic #{api_key}" }

  response = HTTParty.get("http://dev.markitondemand.com/Api/v2/Quote?symbol=#{stockname}")
  jsonresponse = response.to_json
  # puts jsonresponse
  if response.code != 200
   raise "failed to query"
  else
  # util.truncate
   current_price = JSON.parse(jsonresponse)["StockQuote"]
  end
  return current_price
end

def sendNotification(phone_number)
  account_sid = 'ACeba3bb02a35fac346470d0bf1cbfd794' 
  auth_token = '4676d42f22f0ab3f04664ecb86a3de1f' 
 
  # set up a client to talk to the Twilio REST API 
  @client = Twilio::REST::Client.new account_sid, auth_token 
 
  @client.account.messages.create({
    :from => '+19546422747', 
    :to => phone_number, 
    :body => 'Hey Gus! This is an investbot test!', 
  })
end


#def getHistoricalValues(stockname, timeperiod, frequency, type)
#
#  #headers = { "Authorization" => "Basic #{api_key}" }
#
#  response = HTTParty.get("http://dev.markitondemand.com/Api/v2/Quote?symbol=#{stockname}")
#  jsonresponse = response.to_json
#
#  if response.code != 200
#   raise "failed to query"
#  else
#  # util.truncate
#   current_price = JSON.parse(jsonresponse)["StockQuote"]["LastPrice"]
#  end
#
#  return current_price
#end
#
#def buyDecision(stockname, buypricelow, buypricehigh, slope)
#
#  currentprice = getCurrentPrice(stockname)
#
#  if currentprice > buypricelow
#   if currentprice < buypricehigh
#
#
#end



def startProgram(stocks)

#read through config file to grab DB and API info
#config = YAML.load_file("config.yml")

#db_user = config['db_user']
db_user = 'investbot'
#db_pass = config['db_pass']
db_pass = 'investbot123'
#db_host = config['db_host']
db_host = 'investbotdb.c1p7w3xyq4hx.us-east-1.rds.amazonaws.com'
#db_name = config['db_name']
db_name = 'investbotdb'
#api_key = config['api_key']
# get connection to db - replace with connection to RDS
db = Sequel.connect(:adapter => 'mysql2', :user => db_user, :host => db_host, :database => db_name, :password => db_pass)

# get a handle to table
util = db[:stock_price]
  # iterate over data and insert records in table
  stocks.each do |stock_name|
  # print "."
  returned_value = getCurrentPrice(stock_name)
  entry_time = Time.now
   util.insert(
     :stock_name => returned_value["Name"],
     :stock_symbol => returned_value["Symbol"],
     :timestamp => returned_value["Timestamp"],
     :entry_time => entry_time,
     :stock_price => returned_value["LastPrice"]
   )
  sleep(3)
  end
end


stocks = ["KO","DOW","T","GE","GILD","SYK","JPM","UNH","PG","BA","HD","AAPL"]
startProgram(stocks)
