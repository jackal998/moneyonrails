require 'csv'
require 'ftx_client'

namespace :dev do

  task :wss_test => :environment do
    def ws_restart(ws_url)
      ws_start(ws_url, 'restart')
    end

    def ws_start(ws_url, status)
      ts = DateTime.now.strftime('%Q')

      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.credentials.ftx[:GridOnRails][:sec], 
        ts + "websocket_login")

      login_op = {
        op: "login",
        args: {
          key: Rails.application.credentials.ftx[:GridOnRails][:pub],
          sign: signature,
          time: ts.to_i,
          subaccount: "GridOnRails"
        }
      }.to_json
      order_subs = { op: "subscribe", channel: "orders"}.to_json
      ping = { op: "ping"}.to_json

      EM.run {
        ws = Faye::WebSocket::Client.new(ws_url)

        ws.on :open do |event|
          print "#{Time.now.strftime('%H:%M:%S')}:" 
          p "ws open status: #{status}"
          ws.send(login_op)

          ws.send(order_subs)
        end

        ws.on :message do |event|
          valid_message = true
          ws_message = JSON.parse(event.data)

          if ws_message["type"] == "update" && ws_message["channel"] == "orders"
            order_data = ws_message["data"]
            valid_message = false if order_data["market"] == "BTC-PERP"
          end

          print "#{Time.now.strftime('%H:%M:%S')}:" 
          puts ws_message

          unless valid_message
            ws.close
            next
          end
        end

        ws.on :close do |event|
          print "#{Time.now.strftime('%H:%M:%S')}:" 
          p "ws closed with #{event.code}"

          sleep(1)
          ws_restart(ws_url) if event.code == 1006
          EM::stop_event_loop
        end

        EM.add_periodic_timer(58) { 
          ws.send(ping)
        }
      }
    end

    ws_start('wss://ftx.com/ws/', 'new')


    puts "YOYO"
    rs = {"type"=>"subscribed", "channel"=>"orders"}
    ws_r_o = {"channel"=>"orders", "type"=>"update", "data"=>{"id"=>79392399932, "clientId"=>nil, "market"=>"FTT-PERP", "type"=>"limit", "side"=>"buy", "price"=>67.556, "size"=>0.1, "status"=>"new", "filledSize"=>0.0, "remainingSize"=>0.1, "reduceOnly"=>false, "liquidation"=>false, "avgFillPrice"=>nil, "postOnly"=>false, "ioc"=>false, "createdAt"=>"2021-09-14T18:32:52.325084+00:00"}}
    ws_r_filled = {"channel"=>"orders", "type"=>"update", "data"=>{"id"=>79392399932, "clientId"=>nil, "market"=>"FTT-PERP", "type"=>"limit", "side"=>"buy", "price"=>67.556, "size"=>0.1, "status"=>"closed", "filledSize"=>0.1, "remainingSize"=>0.0, "reduceOnly"=>false, "liquidation"=>false, "avgFillPrice"=>67.556, "postOnly"=>false, "ioc"=>false, "createdAt"=>"2021-09-14T18:32:52.325084+00:00"}}
    ws_r_c = {"channel"=>"orders", "type"=>"update", "data"=>{"id"=>79392447727, "clientId"=>nil, "market"=>"FTT-PERP", "type"=>"market", "side"=>"sell", "price"=>nil, "size"=>0.1, "status"=>"closed", "filledSize"=>0.1, "remainingSize"=>0.0, "reduceOnly"=>true, "liquidation"=>false, "avgFillPrice"=>67.512, "postOnly"=>false, "ioc"=>true, "createdAt"=>"2021-09-14T18:33:03.112043+00:00"}}
  end
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

  task :get_logo_png_url_from_ftx_market_html => :environment do
    local_html_path = "./lib/FTX _markets.html"
    # 因為純粹HTML裡面沒有這麼多資料可以用...
    name_found = 0

    ftx_market_html = File.read(local_html_path)
    document = Nokogiri::HTML.parse(ftx_market_html)

    document.at('tbody').search('tr').each do |row|
      row_a = row.at('a')
      name_found += 1
      print name_found
      p market_name = row_a["href"].split("https://ftx.com/trade/")[1]
      # puts row_a.at('img')['src']
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

    data = FtxClient.funding_payments("MoneyOnRails",{:start_time => query_end_time.to_i})
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

    orders_updated = 0
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
          orders_updated += 1
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

    puts "update_funding_payment of #{orders_updated} orders ok => #{Time.now} (#{Time.now - init_time}s)"
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
          data = FtxClient.funding_payments("MoneyOnRails", {:future => "#{coin_name}-PERP",:start_time => start_time,:end_time => end_time})

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
  
  task :update_funding_status => :environment do
    init_time = Time.now

    db_data = FundingPayment.order("time asc").pluck(:coin_id, :coin_name, :time, :payment, :rate).map { |coin_id, coin_name, time, payment, rate| {coin_id: coin_id, coin_name: coin_name, time: time, payment: payment, rate: rate}}
    fundingpayments = db_data.group_by{|fp| fp[:coin_name]}.transform_values {|k| k.group_by_day(format: '%F') { |fp| fp[:time] }}

    funding_status_datas_tbu = []

    days_rng = [:historical,90,60,30,14,7,3,1]

    total_funding_status = FundingStat.new(:coin_name => "total_of_coins", :created_at => init_time, :updated_at => init_time)
    fundingpayments.each do |coin_name, dataset|
      funding_status = FundingStat.new(:coin_id => dataset.first[1].first[:coin_id], :coin_name => coin_name, :created_at => init_time, :updated_at => init_time)

      dataset.each do |day, data_arr|
        data_arr.each do |data|

          payment = 0 - data[:payment]
          rate = data[:rate]

          days_rng.each do |d|
            sym_payment = d == :historical ? "#{d}_payments".to_sym : "last_#{d}_day_payments".to_sym
            sym_irr = d == :historical ? "#{d}_irr".to_sym : "last_#{d}_day_irr".to_sym
            if d == :historical || day >= d.day.ago
              # irr used as tmp storage of cost for real irr calc
              funding_status[sym_payment] += payment
              funding_status[sym_irr] +=  payment / rate unless rate == 0

              total_funding_status[sym_payment] += payment
              total_funding_status[sym_irr] +=  payment / rate unless rate == 0
            else
              break
            end
          end
        end
      end
      
      days_rng.each do |d|
        sym_payment = d == :historical ? "#{d}_payments".to_sym : "last_#{d}_day_payments".to_sym
        sym_irr = d == :historical ? "#{d}_irr".to_sym : "last_#{d}_day_irr".to_sym
        # irr used as tmp storage of cost for real irr calc
        funding_status[sym_irr] = ((funding_status[sym_payment] / funding_status[sym_irr])* 24 * 365 * 100).round(2) if funding_status[sym_irr] != 0
        funding_status[sym_payment] = funding_status[sym_payment].round(2)
      end
      funding_status_datas_tbu << funding_status.attributes.except!("id")
    end

    days_rng.each do |d|
      sym_payment = d == :historical ? "#{d}_payments".to_sym : "last_#{d}_day_payments".to_sym
      sym_irr = d == :historical ? "#{d}_irr".to_sym : "last_#{d}_day_irr".to_sym

      total_funding_status[sym_irr] =  ((total_funding_status[sym_payment] / total_funding_status[sym_irr])* 24 * 365 * 100).round(2) if total_funding_status[sym_irr] != 0
      total_funding_status[sym_payment] = total_funding_status[sym_payment].round(2)
    end

    funding_status_datas_tbu << total_funding_status.attributes.except!("id")

    FundingStat.delete_all
    FundingStat.upsert_all(funding_status_datas_tbu)
    puts "update_funding_status ok => #{Time.now} (#{Time.now - init_time}s)"
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

    rate_datas_tbu = []
    tmp = data["result"].index_by {|result| "#{result["future"].split('-')[0]}"}

    tmp.except!("DMG")
    datas_count = tmp.count

    # check if datas are aligned and ready to be update
    # 2021/09/02 DMG 在亂...FTX上面沒有PERP，但API回傳有他的Rate...，先手動當例外處裡(149coins)
    puts 'tmp.except!("DMG")'
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
          \r#{err_msg}
          \rrecorded coins:         #{coins_to_update}
          \rrecorded rates (1/2hr): #{last_1hr_rates_count}/#{last_2hr_rates_count}
          \rapi response datas:     #{datas_count}"
      next # this means abort task ... do block
    end

    # update start
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