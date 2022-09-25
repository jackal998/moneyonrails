require "csv"

namespace :dev do
  task wss_test: :environment do
    def ws_restart(ws_url)
      ws_start(ws_url, "restart")
    end

    def ws_start(ws_url, status)
      ts = DateTime.now.strftime("%Q")

      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.credentials.ftx[:GridOnRails][:sec],
        ts + "websocket_login"
      )

      login_op = {
        op: "login",
        args: {
          key: Rails.application.credentials.ftx[:GridOnRails][:pub],
          sign: signature,
          time: ts.to_i,
          subaccount: "GridOnRails"
        }
      }.to_json
      order_subs = {op: "subscribe", channel: "orders"}.to_json
      ping = {op: "ping"}.to_json

      EM.run {
        ws = Faye::WebSocket::Client.new(ws_url)
        datas = []
        ws.on :open do |event|
          print "#{Time.now.strftime("%H:%M:%S")}:"
          p "ws open status: #{status}"
          ws.send(login_op)
          ws.send(order_subs)
        end

        ws.on :message do |event|
          valid_message = true
          ws_message = JSON.parse(event.data)

          if ws_message["type"] == "update" && ws_message["channel"] == "orders"
            order_data = ws_message["data"]
            datas << order_data

            valid_message = false if order_data["market"] == "BTC-PERP"
          end

          print "#{Time.now.strftime("%H:%M:%S")}:"
          puts ws_message

          ws.close unless valid_message
        end

        ws.on :close do |event|
          print "#{Time.now.strftime("%H:%M:%S")}:"
          p "ws closed with #{event.code}"

          sleep(1)
          ws_restart(ws_url) if event.code == 1006
          EM.stop_event_loop
        end

        EM.add_periodic_timer(58) {
          ws_orders = datas.dup
          datas -= ws_orders

          listed = {}
          ws_orders.each { |o| listed[o["id"]] = o }
          valid_orders = listed.map { |key, value| value }

          ws.send(ping)
        }
      }
    end

    ws_start("wss://ftx.com/ws/", "new")
    puts "YOYO"
  end

  task update_coins_weight_from_csv_file: :environment do
    coins = Coin.all
    weights = {}
    coins_tbu = []
    counter = 0

    CSV.foreach("#{Rails.root}/tmp/coin_weight.csv", headers: true) do |row|
      rh = row.to_hash
      weights[rh["Coin"]] = rh["Weight (total)"]
    end

    coins.each do |coin|
      weights[coin.name] = 0 unless weights[coin.name]
      if coin["weight"].to_f != weights[coin.name].to_f
        puts "#{coin.name} weight changed from #{coin["weight"]} to #{weights[coin.name]}"
        coin["weight"] = weights[coin.name]
        coin["updated_at"] = Time.now

        counter += 1
        coins_tbu << coin.attributes.except!("name")
      end
    end

    Coin.upsert_all(coins_tbu) unless coins_tbu.empty?
    puts "Updated: #{counter}"
  end

  task import_funding_payment_from_csv_file: :environment do
    init_time = Time.now
    coin = Coin.find_by(name: "")

    puts "import_funding_payment_from_csv_file of #{coin.name} start at #{init_time}"

    data_counts = 0
    data_exists = 0
    funding_payment_datas_tbu = []
    funding_payment_datas_exist = []

    CSV.foreach("#{Rails.root}/tmp/funding_payment.csv", headers: true) do |row|
      rh = row.to_hash
      next unless rh["future"].split("-")[0] == coin.name

      funding_payment = FundingPayment.find_by(coin_name: coin.name, time: rh["time"].to_time)

      if funding_payment.nil?
        funding_payment = FundingPayment.new(
          coin_id: coin.id,
          coin_name: coin.name,
          payment: rh["payment"],
          rate: rh["rate"],
          time: rh["time"],
          created_at: Time.now,
          updated_at: Time.now
        )
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

  task get_logo_png_url_from_ftx_market_html: :environment do
    local_html_path = "./lib/FTX _markets.html"
    # 因為純粹HTML裡面沒有這麼多資料可以用...
    name_found = 0

    ftx_market_html = File.read(local_html_path)
    document = Nokogiri::HTML.parse(ftx_market_html)

    document.at("tbody").search("tr").each do |row|
      row_a = row.at("a")
      name_found += 1
      print name_found
      p market_name = row_a["href"].split("https://ftx.com/trade/")[1]
      # puts row_a.at('img')['src']
    end
  end
end
