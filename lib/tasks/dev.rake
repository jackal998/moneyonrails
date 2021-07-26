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

    now_time_i = now_time.to_i

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

      if datas_lag > 0
        # get first data from very early date
        while end_time < now_time_i

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

      calc_rate_stats!(c)
    end
    puts "fetch_history_rate updated to time #{now_time}"
  end

  def calc_rate_stats!(c)

    success_rate_past_48_hrs = 0.00
    success_rate_past_week = 0.00
    irr_past_week = 1
    irr_past_month = 1

    last_hour = Time.now.beginning_of_hour
    last_48_hrs = last_hour - 2 * 24 * 3600
    last_week = last_hour - 7 * 24 * 3600
    last_month = last_hour - 30 * 24 * 3600

    cr_last_month = c.rates.readonly.where("time > ?", last_month).order(time: :asc)
    
    cr_last_month.each do |r|
      irr_past_month = (irr_past_month * (1 + r.rate)).round(6)
      if r.time > last_week
        irr_past_week = (irr_past_week * (1 + r.rate)).round(6)
        if r.rate > 0
          success_rate_past_week += 1
          success_rate_past_48_hrs += 1 if r.time > (last_48_hrs)
        end
      end
    end

    success_rate_past_48_hrs = (success_rate_past_48_hrs / 48).round(5)
    success_rate_past_week = ((success_rate_past_week / (7 * 24))).round(5)
    irr_past_week = (((irr_past_week - 1) / 7) * 365).round(3)
    irr_past_month = ((irr_past_month - 1) * 12).round(3)

    crs = c.current_fund_stat ? c.current_fund_stat : CurrentFundStat.new(:coin => c)

    crs.assign_attributes(
      :success_rate_past_48_hrs => success_rate_past_48_hrs,
      :success_rate_past_week => success_rate_past_week,
      :irr_past_week => irr_past_week,
      :irr_past_month => irr_past_month)

    crs.save
  end  
end