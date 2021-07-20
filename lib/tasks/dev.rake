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

    now_time = Time.now.beginning_of_hour

    puts "Fetching history rate... => #{now_time}"

    now_time = now_time.to_i

    coins = Coin.all
    coin_counter = 0
    coins_to_updates = coins.count

    puts "#{coins_to_updates} coins to be updated"

    coins.each do |c|

      # init conditions
      coin_counter += 1
      puts "(#{coin_counter}/#{coins_to_updates}) #{c.name}..."

      if c.rates.empty?
        lastest_data_time = "2019-03-01T00:00:00+00:00".to_time
      else
        lastest_data_time = c.rates.order("time").last.time
      end

      datas_lag = ((Time.now - lastest_data_time)/3600).floor

      puts "Lastest data: #{lastest_data_time}, #{datas_lag} datas to be updated"

      start_time = lastest_data_time.to_i + 1
      end_time = 0

      success = 0
      failed_records = []

      # get first data from very early date
      while end_time < now_time

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

      puts "Imported: #{success}/#{datas_lag}，Failed: #{failed_records.size}/#{datas_lag}"
      
      failed_records.each do |record|
        puts "#{record.coin.name + record.time.to_s} ---> #{record.time.errors.full_messages}"
      end
    end
  end

end