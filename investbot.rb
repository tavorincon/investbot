#!/usr/bin/env ruby

require 'httparty'
require 'nokogiri'
#require 'sequel'
#require 'json'
#require 'date'
#require 'yaml'

#read through config file to grab DB and API info
#config = YAML.load_file("../conf/config.yml")

#db_user = config['db_user']
#db_pass = config['db_pass']
#db_host = config['db_host']
#db_name = config['db_name']
#api_key = config['api_key']

# get connection to db - replace with connection to RDS
#db = Sequel.connect(:adapter => 'mysql2', :user => db_user, :host => db_host, :database => db_name, :password => db_pass)

#puts db

# get a handle to table
#util = db[:db_name]

#puts util

# GET data from API


def getCurrentPrice(stockname)

  #headers = { "Authorization" => "Basic #{api_key}" }

  response = HTTParty.get("http://dev.markitondemand.com/Api/v2/Quote?symbol=#{stockname}")
  jsonresponse = response.to_json

  if response.code != 200
   raise "failed to query"
  else
  # util.truncate
   current_price = JSON.parse(jsonresponse)["StockQuote"]["LastPrice"]
  end

  return current_price
end

# iterate over data and insert records in table
#records.each do |row|
# print "."
# util.insert(
#   :business_unit_id => row["business_unit_id"],
# )
#end
