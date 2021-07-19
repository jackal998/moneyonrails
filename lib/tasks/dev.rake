require 'csv'

namespace :dev do

  task :import_coins_csv_file => :environment do

    success = 0
    failed_records = []

  	CSV.foreach("#{Rails.root}/tmp/coin_seed.csv", headers: true) do |row|
  	  coin = Coin.new(row.to_hash)
      if coin.save
        success += 1
      else
        failed_records << [row, coin]
      end
  	end

    puts "總共匯入 #{success} 筆，失敗 #{failed_records.size} 筆"
    failed_records.each do |record|
      puts "#{record[0]} ---> #{record[1].errors.full_messages}"
    end
  end


  task :fetch_history_rate => :environment do
    puts "Fetching history rate..."

    lastest_time = Time.now.beginning_of_hour.to_i

    # init conditions
    c = Coin.find_by(:name => "BTC")

    if c.rates.empty?
      start_time = "2019-01-06T14:00:01+00:00".to_time.to_i
    else
      start_time = c.rates.order("time").last.time.to_i + 1
    end
    end_time = 0

    success = 0
    failed_records = []

    # get first data from very early date
    while end_time < lastest_time

      start_time = end_time unless end_time == 0
      end_time = start_time + 495 * 3600 

      ftxurl = "https://ftx.com/api/funding_rates?future=#{c.name}-PERP&start_time=#{start_time}&end_time=#{end_time}"

      response = RestClient.get ftxurl
      data = JSON.parse(response.body)

      data["result"].each do |result|
        r = Rate.new(:name => result["future"],:rate => result["rate"],:time => result["time"],:coin => c)
        
        if r.save
          success += 1
        else
          failed_records << [r]
        end
      end 
    end

    puts "總共匯入 #{success} 筆，失敗 #{failed_records.size} 筆"
    
    failed_records.each do |record|
      puts "#{record.coin.name + record.time.to_s} ---> #{record.time.errors.full_messages}"
    end

  end
end