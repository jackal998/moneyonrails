require 'csv'
require 'ftx_client'

namespace :dev do

  # Seed
  task :update_coins_seed_from_csv_file => :environment do

    success = 0
    failed_records = []

  	CSV.foreach("#{Rails.root}/tmp/coin_seed.csv", headers: true) do |row|
      rh = row.to_hash
      coin = Coin.find(rh["id"]) || Coin.new
      rh.keys.each do |k|
        next if k == "id" || k == "name"
        coin[k] = rh[k]
      end

      if coin.save
        success += 1
      else
        failed_records << [row, coin]
      end
    end

    puts "Updated: #{success}，Failed: #{failed_records.size}"
    failed_records.each do |record|
      puts "#{record[0]} ---> #{record[1].errors.full_messages}"
    end
  end

  task :get_funding_infos => :environment do
    cst = Time.now
    coins = Coin.includes(:current_fund_stat).where("have_perp = ?", true)

    fund_stat_datas_tbu = []

    coins.each do |c|
    # finding ways to websocket ftx...
      data = FtxClient.future_stats("#{c.name}-PERP")

      append_fund_stat_data(c.current_fund_stat, data["result"], fund_stat_datas_tbu)
    end
    
    CurrentFundStat.upsert_all(fund_stat_datas_tbu)

    puts "get_funding_infos ok => #{Time.now} (#{Time.now - cst}s)"
  end

  task :update_funding_payment => :environment do
    init_time = Time.now
    now_time = init_time.beginning_of_hour
    now_time_i = now_time.to_i

    data = FtxClient.funding_payments({:start_time => now_time_i})

    coins = Coin.includes(:funding_orders, :funding_payments).where(id: FundingOrder.where(:order_status => "Close").distinct.pluck(:coin_id))

    coins_to_update = coins.count
    last_1hr_funding_payments_count = FundingPayment.where("time >= ?",now_time).count
    last_2hr_funding_payments_count = FundingPayment.where("time >= ?",now_time - 1.hour).count
    datas_count = data["result"].count

    # check if datas are aligned and ready to be update
    case
    when datas_count == coins_to_update && last_2hr_funding_payments_count == coins_to_update * 2
      err_msg = "FundingPayments already up-to-date, no data was imported."
    when datas_count > coins_to_update
      err_msg = "Please update coins list first  => rails c > `helper.update_market_infos`
               \rthen update history funding_payments data  => `rake dev:fetch_history_funding_payment`"
    else
      err_msg = "Update history funding_payments data first => `rake dev:fetch_history_funding_payment`"
    end
    unless coins_to_update == last_2hr_funding_payments_count && last_2hr_funding_payments_count == datas_count
      puts "update_rate: abort: Data counts missmatch.
        \n\r#{err_msg}
        \n\rrecorded coins:                    #{coins_to_update}
          \rrecorded funding payments (1/2hr): #{last_1hr_funding_payments_count}/#{last_2hr_funding_payments_count}
          \rapi response datas:                #{datas_count}"
      next # this means abort task ... do block
    end

    # update start
    puts "Updating rate... => #{now_time}"

    funding_payment_datas_tbu = []
    tmp = data["result"].index_by {|result| "#{result["future"].split('-')[0]}"}

    coins.each do |coin|
      funding_payment = FundingPayment.new(
        :coin_id => coin.id,
        :coin_name => coin.name, 
        :payment => tmp[coin.name]["payment"],
        :rate => tmp[coin.name]["rate"],
        :time => tmp[coin.name]["time"],
        :created_at => Time.now,
        :updated_at => Time.now)

      funding_payment_datas_tbu << funding_payment.attributes.except!("id")
    end
    FundingPayment.insert_all(funding_payment_datas_tbu)

    puts "update_funding_payment of #{coins_to_update} coins ok => #{Time.now} (#{Time.now - init_time}s)"
  end

  task :fetch_history_funding_payment => :environment do
    init_time = Time.now
    now_time = Time.now.beginning_of_hour

    puts "Fetching history funding payment... => #{Time.now}"

    now_time_i = now_time.to_i

    coins = Coin.includes(:funding_orders, :funding_payments).where(id: FundingOrder.where(:order_status => "Close").distinct.pluck(:coin_id))

    coin_counter = 0
    coins_to_updates = coins.count

    puts "#{coins_to_updates} coins to be updated"

    coins.each do |c|

      coin_counter += 1

      funding_orders = c.funding_orders.where(:order_status => "Close").order("created_at asc")
      funding_payments = c.funding_payments.order("created_at asc")

      if funding_payments.empty?
        lastest_data_time = funding_orders.first.updated_at
      else
        lastest_data_time = funding_payments.last.time
      end

      datas_lag = ((Time.now - lastest_data_time)/3600).floor

      print "(#{coin_counter}/#{coins_to_updates}) #{c.name}...#{datas_lag} to be updated..."

      start_time = lastest_data_time.to_i + 1
      end_time = 0

      success = 0
      failed_records = []

      if datas_lag > 0
        # get first data from very early date
        while end_time < now_time_i

          start_time = end_time unless end_time == 0
          end_time = start_time + 495 * 3600 

          # start_time        number  1559881511  optional
          # end_time          number  1559881711  optional
          # future            string  BTC-PERP    optional
          data = FtxClient.funding_payments({:future => "#{c.name}-PERP",:start_time => start_time,:end_time => end_time})

          data["result"].each do |result|
            r = FundingPayment.new(:coin_id => c.id, :coin_name => c.name, :payment => result["payment"], :rate => result["rate"], :time => result["time"])

            if r.save
              success += 1
            else
              failed_records << [r]
            end
          end 
        end
      end
      puts "Imported: #{success}/#{datas_lag}"
    end

    puts "fetch_history_rate to time #{now_time} ok => #{Time.now} (#{Time.now - init_time}s)"
  end

  task :update_rate => :environment do
    init_time = Time.now
    now_time = init_time.beginning_of_hour
    now_time_i = now_time.to_i

    data = FtxClient.funding_rates({:start_time => now_time_i})

    coins = Coin.includes(:current_fund_stat).where("have_perp = ?", true)
    coins_to_update = coins.count
    last_1hr_rates_count = Rate.where("time >= ?",now_time).count
    last_2hr_rates_count = Rate.where("time >= ?",now_time - 1.hour).count
    datas_count = data["result"].count

    # check if datas are aligned and ready to be update
    case
    when datas_count == coins_to_update && last_2hr_rates_count == coins_to_update * 2
      err_msg = "Rates already up-to-date, no data was imported."
    when datas_count > coins_to_update
      err_msg = "Please update coins list first  => rails c > `helper.update_market_infos`
               \rthen update history rates data  => `rake dev:fetch_history_rate`"
    else
      err_msg = "Update history rates data first => `rake dev:fetch_history_rate`"
    end
    unless coins_to_update == last_2hr_rates_count && last_2hr_rates_count == datas_count
      puts "update_rate: abort: Data counts missmatch.
        \n\r#{err_msg}
        \n\rrecorded coins:         #{coins_to_update}
          \rrecorded rates (1/2hr): #{last_1hr_rates_count}/#{last_2hr_rates_count}
          \rapi response datas:     #{datas_count}"
      next # this means abort task ... do block
    end

    # update start
    puts "Updating rate... => #{now_time}"

    rate_datas_tbu = []
    tmp = data["result"].index_by {|result| "#{result["future"].split('-')[0]}"}

    coins.each do |coin|
      rate = Rate.new(
        :coin_id => coin.id,
        :name => tmp[coin.name]["future"],
        :rate => tmp[coin.name]["rate"],
        :time => tmp[coin.name]["time"],
        :created_at => Time.now,
        :updated_at => Time.now)

      rate_datas_tbu << rate.attributes.except!("id")
    end
    Rate.insert_all(rate_datas_tbu)

    update_rate_stats(coins)

    puts "update_rate of #{coins_to_update} coins ok => #{Time.now} (#{Time.now - init_time}s)"
  end
  
  # Coin.all by each fecth every data to now, need some DB i/o modify (2021/07/28)
  task :fetch_history_rate => :environment do
    init_time = Time.now
    now_time = Time.now.beginning_of_hour

    puts "Fetching history rate... => #{Time.now}"

    now_time_i = now_time.to_i

    coins = Coin.includes(:current_fund_stat).where("have_perp = ?", true)
    coin_counter = 0
    coins_to_updates = coins.count

    puts "#{coins_to_updates} coins to be updated"

    coins.each do |c|

      # init conditions
      coin_counter += 1

      if c.rates.empty?
        lastest_data_time = "2019-03-01T00:00:00+00:00".to_time
      else
        lastest_data_time = c.rates.order("time").last.time
      end

      datas_lag = ((Time.now - lastest_data_time)/3600).floor

      print "(#{coin_counter}/#{coins_to_updates}) #{c.name}...#{datas_lag} to be updated..."

      start_time = lastest_data_time.to_i + 1
      end_time = 0

      success = 0
      failed_records = []

      if datas_lag > 0
        # get first data from very early date
        while end_time < now_time_i

          start_time = end_time unless end_time == 0
          end_time = start_time + 495 * 3600 

          data = FtxClient.funding_rates({:future => "#{c.name}-PERP",:start_time => start_time,:end_time => end_time})

          data["result"].each do |result|
            r = Rate.new(:name => result["future"],:rate => result["rate"],:time => result["time"],:coin => c)
            
            if r.save
              success += 1
            else
              failed_records << [r]
            end
          end 
        end
      end
      puts "Imported: #{success}/#{datas_lag}"
    end

    update_rate_stats(coins)

    puts "fetch_history_rate to time #{now_time} ok => #{Time.now} (#{Time.now - init_time}s)"
  end

private
  def update_rate_stats(coins)
    fund_stat_datas_tbu = []
    coins.each {|coin| fund_stat_datas_tbu << calc_rate_stats(coin)}
    CurrentFundStat.upsert_all(fund_stat_datas_tbu)
  end

  def calc_rate_stats(c)

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

    crs = c.current_fund_stat ? c.current_fund_stat : CurrentFundStat.new(:coin => c,:created_at => Time.now,:updated_at => Time.now)

    crs.assign_attributes(
      :rate => cr_last_month.last.rate,
      :success_rate_past_48_hrs => success_rate_past_48_hrs,
      :success_rate_past_week => success_rate_past_week,
      :irr_past_week => irr_past_week,
      :irr_past_month => irr_past_month,
      :updated_at => Time.now)

    return crs.attributes
  end

  def append_fund_stat_data(fund_stat, data, data_arr)
    fund_stat.assign_attributes(
      :nextFundingRate => data["nextFundingRate"],
      :nextFundingTime => data["nextFundingTime"],
      :openInterest => data["openInterest"],
      :updated_at => Time.now)
    
    data_arr << fund_stat.attributes
  end
end