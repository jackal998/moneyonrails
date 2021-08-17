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

  task :import_funding_payment_from_csv_file => :environment do
    init_time = Time.now
    coin = Coin.find_by(name: "")

    puts "import_funding_payment_from_csv_file of #{coin.name} start at #{init_time}"

    data_counts = 0
    data_exists = 0
    funding_payment_datas_tbu = []
    funding_payment_datas_exist = []

    CSV.foreach("#{Rails.root}/tmp/funding_payment.csv", headers: true) do |row|
      rh = row.to_hash
      next unless rh['future'].split('-')[0] == coin.name

      funding_payment = FundingPayment.find_by(coin_name: coin.name, time: rh["time"].to_time)

      if funding_payment.nil?
        funding_payment = FundingPayment.new(
          :coin_id => coin.id,
          :coin_name => coin.name, 
          :payment => rh["payment"],
          :rate => rh["rate"],
          :time => rh["time"],
          :created_at => Time.now,
          :updated_at => Time.now)
          data_counts += 1
          funding_payment_datas_tbu << funding_payment.attributes.except!("id")
      else
        # # Manual force updae start
        # funding_payment[:payment] = rh["payment"]
        # funding_payment[:updated_at] = Time.now
        # data_counts += 1
        # funding_payment_datas_tbu << funding_payment.attributes
        # # Manual force updae end
        
        data_exists += 1
        funding_payment_datas_exist << funding_payment[:id]
      end
    end
    
    FundingPayment.upsert_all(funding_payment_datas_tbu) unless funding_payment_datas_tbu.empty?

    puts "#{data_exists} datas exists. \n#{funding_payment_datas_exist}" unless funding_payment_datas_exist.empty?
    puts "import_funding_payment_from_csv_file of #{coin.name} with #{data_counts} new records ok => #{Time.now} (#{Time.now - init_time}s)"
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
    query_end_time = init_time.beginning_of_hour
    last_data_time = init_time.beginning_of_hour - 1.hour

    funding_payments = {}
    funding_payments[query_end_time] = {}
    funding_payments[last_data_time] = {}

    FundingPayment.where("time >= ?", last_data_time).map {|fp| funding_payments[fp[:time]][fp[:coin_name]] = fp }
    
    # next # this means abort task ... do block
    if funding_payments[query_end_time].count > 0
      err_msg = "FundingPayments with #{funding_payments[query_end_time].count} records already up-to-date, no data was imported."
      puts err_msg
      next
    end

    updated_status = {}
    funding_orders = {}
    FundingOrder.includes(:coin).select('DISTINCT ON ("coin_id") *').where(:order_status => ["Close","Underway"]).order(:coin_id, created_at: :desc).map {|fo| funding_orders[fo[:coin_name]] = fo}

    recent_orders = FundingOrder.includes(:coin).where("created_at > ?", last_data_time).where(:order_status => ["Close","Underway"]).order(:coin_id, created_at: :asc).group_by(&:coin_name)

    orders_to_be_updated = 0
    funding_orders.each do |coin_name, funding_order|
      case
      when recent_orders[coin_name]
        case 
        when recent_orders[coin_name].first[:original_perp_amount] == 0 && recent_orders[coin_name].last[:target_perp_amount] != 0
          updated_status[coin_name] = "new"
          orders_to_be_updated += 1
        when recent_orders[coin_name].first[:original_perp_amount] != 0 && recent_orders[coin_name].last[:target_perp_amount] != 0
          updated_status[coin_name] = "normal"
          orders_to_be_updated += 1
        when  recent_orders[coin_name].last[:target_perp_amount] == 0
          updated_status[coin_name] = "down"
        end  
      when (funding_order[:order_status] == "Close" && funding_order[:target_perp_amount] != 0 && funding_order[:updated_at] <= query_end_time) ||
           (funding_order[:order_status] == "Underway" && funding_order[:original_perp_amount] != 0 && funding_order[:target_perp_amount] != 0) ||
           (funding_order[:order_status] == "Underway" && funding_order[:target_perp_amount] == 0)
        updated_status[coin_name] = "normal"
        orders_to_be_updated += 1

      when funding_order[:order_status] == "Close" && funding_order[:target_perp_amount] == 0 && funding_order[:updated_at] <= query_end_time
        updated_status[coin_name] = "down"

      when funding_order[:order_status] == "Underway"
        updated_status[coin_name] = "underway"
      end
    end

    funding_payment_datas_tbu = []

    data = FtxClient.funding_payments({:start_time => query_end_time.to_i})
    data_results = data["result"].index_by {|result| "#{result["future"].split('-')[0]}"}
    datas_count = data_results.count

    data_results.each do |coin_name, data_result|

      case updated_status[coin_name]
      when "normal"
        updated_status[coin_name] = "missing data" unless funding_payments[last_data_time][coin_name]
      when "new", "underway"

      when nil
        # 沒有訂單，卻有data，原則上是手動建立的
        updated_status[coin_name] = "missing order status"
      end
    end

    updated_status.each do |coin_name, status|
      case status
      when "down"
        next
      when "normal", "underway", "new"
        if data_results[coin_name]
          funding_payment = FundingPayment.new(
            :coin_id => funding_orders[coin_name][:coin_id],
            :coin_name => coin_name, 
            :payment => data_results[coin_name]["payment"],
            :rate => data_results[coin_name]["rate"],
            :time => data_results[coin_name]["time"],
            :created_at => Time.now,
            :updated_at => Time.now)
          funding_payment_datas_tbu << funding_payment.attributes.except!("id")
        else
          puts "#{coin_name} order #{funding_orders[coin_name][:id]} status normal, but no data from FTX" if status == "normal"
        end

      when "missing data"
        puts "#{coin_name} missing data, please check and update history rates data => `rake dev:fetch_history_funding_payment`"
        exit
      when "missing order status"
        puts "#{coin_name} missing order status, please check."
        exit
      else
        puts "Abort: #{coin_name} with #{status}"
        exit
      end
    end

    FundingPayment.insert_all(funding_payment_datas_tbu)

    puts "update_funding_payment of #{orders_to_be_updated} orders ok => #{Time.now} (#{Time.now - init_time}s)"
  end

  task :fetch_history_funding_payment => :environment do
    init_time = Time.now

    puts "Fetching history funding payment... => #{init_time}"

    funding_orders = {}
    FundingOrder.select('DISTINCT ON ("coin_id") *').where(:order_status => ["Close","Underway"]).order(:coin_id, created_at: :desc).map {|fo| funding_orders[fo[:coin_name]] = fo}

    funding_payments = {}
    FundingPayment.select('DISTINCT ON ("coin_id") *').order(:coin_id, time: :desc).map {|fp| funding_payments[fp[:coin_name]] = fp}

    order_counter = 0
    order_zero_ed = 0
    orders_to_updates = funding_orders.size

    puts "#{orders_to_updates} orders to be updated"

    funding_orders.each do |coin_name, funding_order|

      order_counter += 1

      funding_payment = funding_payments[coin_name]

      lastest_data_time = funding_payment ? funding_payment[:time] : funding_order[:created_at].beginning_of_hour

      if funding_order[:order_status] == "Close" && funding_order[:target_perp_amount] == 0
        query_end_time = funding_order[:updated_at].beginning_of_hour
        order_zero_ed += 1
      else
        query_end_time = init_time.beginning_of_hour
      end

      lastest_data_time = lastest_data_time.to_i + 1
      query_end_time = query_end_time.to_i + 1

      datas_lag = ((query_end_time - lastest_data_time)/3600).floor   

      print "(#{order_counter}/#{orders_to_updates}) #{coin_name}...#{datas_lag} to be updated..."

      # params for Ftx query
      start_time = lastest_data_time
      end_time = 0

      success = 0
      failed_records = []

      if datas_lag > 0
        # get first data from very early date
        while end_time < query_end_time

          start_time = end_time unless end_time == 0
          end_time = start_time + 495 * 3600 

          # start_time        number  1559881511  optional
          # end_time          number  1559881711  optional
          # future            string  BTC-PERP    optional
          data = FtxClient.funding_payments({:future => "#{coin_name}-PERP",:start_time => start_time,:end_time => end_time})

          data["result"].each do |result|
            r = FundingPayment.new(:coin_id => funding_order[:coin_id], :coin_name => coin_name, :payment => result["payment"], :rate => result["rate"], :time => result["time"])

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

    puts "fetch_history_rate to time #{init_time.beginning_of_hour} ok => #{Time.now} (#{Time.now - init_time}s)"
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
    # puts "Updating rate... => #{now_time}"

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