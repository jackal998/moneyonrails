class GridExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(grid_setting_id)
    @grid_setting = GridSetting.includes(:grid_orders).find(grid_setting_id)

    return unless params_check(@grid_setting)

    puts console_prefix(@grid_setting) + "sidekiq GridExecutorJob starting..."

    grid_orders_init!(@grid_setting)
    puts console_prefix(@grid_setting) + "init orders ok."

    # main loop
    ws_start('new', @grid_setting)

    puts console_prefix(@grid_setting) + "market_name: #{@grid_setting["market_name"]} close ok, See You!"
  end

  def params_check(grid_setting)
    return false unless grid_setting["status"] == "active"
    
    check_value = {}
    upper_limit, lower_limit = grid_setting["upper_limit"], grid_setting["lower_limit"]
    grids, grid_gap = grid_setting["grids"], grid_setting["grid_gap"]
    price_step = grid_setting["price_step"]

    puts "setting market_name      = #{grid_setting["market_name"]}"
    puts "setting upper_limit      = #{upper_limit}"
    puts "setting lower_limit      = #{lower_limit}"
    puts "setting grids            = #{grids}"
    puts "setting grid_gap         = #{grid_gap}"
    puts "setting price_step       = #{price_step}"

    check_value["grids"] = ((upper_limit - lower_limit)/price_step + 1)
    check_value["grid_gap"] = (((upper_limit - lower_limit)/price_step)/(grids - 1)).round(0) * price_step
    check_value["upper_limit"] = lower_limit + ((grids - 1) * grid_gap)


    ["grids","grid_gap","upper_limit"].each do |item|
      compare_sym = ""
      case item
      when "grids"
        compare_sym = ">" if grid_setting[item] > check_value[item]
      else
        compare_sym = "!=" unless grid_setting[item] == check_value[item]
      end

      unless compare_sym == ""
        error_msg = console_prefix(grid_setting) + item + ": #{grid_setting[item]} #{compare_sym} check_value: #{check_value[item]}, invalid."
        puts error_msg
        grid_setting.update(status: "#{item}_error")
        return false
      end
    end

    return true
  end

  def grid_orders_init!(grid_setting)
    market_name = grid_setting["market_name"]

    # 1. Get Current Market price for buy/sell grids caculation
    @market = FtxClient.market_info(market_name)["result"]
    buy_grids = grids_calc("buy", @market["price"], grid_setting)
    sell_grids = grids_calc("sell", @market["price"], grid_setting)
    puts console_prefix(grid_setting) + "market_name: #{market_name} / sell_grids: #{sell_grids} / buy_grids: #{buy_grids}"

    # 2. Get Current Open Orders for missing(init) buy/sell amounts caculation
    @open_orders = FtxClient.open_orders("GridOnRails", market: market_name)["result"].select {|order| order["createdAt"] > grid_setting.created_at}
    bias_required_amount = bias_required_calc(grid_setting, buy_grids, sell_grids, @open_orders)

    # 3. Update orders informations from ftx after bias_required_amount_exec orders
    @market_orders = bias_required_amount_exec(grid_setting, bias_required_amount)
    puts console_prefix(grid_setting) + "orders_status after bias_required_amount_exec: " + create_or_update_orders_status!(grid_setting, @market_orders).to_s

    # 4. Place buy/sell grid orders and Update orders informations from ftx after place orders
    @sell_grids_orders = gird_orders_exec("sell", sell_grids, @market["price"], grid_setting, @open_orders)
    @buy_grids_orders = gird_orders_exec("buy", buy_grids, @market["price"], grid_setting, @open_orders)

    puts console_prefix(grid_setting) + "orders_status after sell gird_orders_exec: " + create_or_update_orders_status!(grid_setting, @sell_grids_orders).to_s
    puts console_prefix(grid_setting) + "orders_status after buy gird_orders_exec: " + create_or_update_orders_status!(grid_setting, @buy_grids_orders).to_s
  end

  def ws_op(op_name, channel = "")
    case op_name
    when "login"
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
          subaccount: "GridOnRails"}}.to_json

      return login_op
    when "subscribe"
      return { op: "subscribe", channel: channel}.to_json
    when "ping"
      return { op: "ping"}.to_json
    end
  end

  def ws_restart(grid_setting)

    grid_orders_init!(grid_setting)
    puts console_prefix(grid_setting) + "init orders for ws restart ok."

    ws_start('restart', grid_setting)
  end

  def ws_start(status, grid_setting)
    market_name = grid_setting["market_name"]
    close_price = grid_setting["upper_limit"] + grid_setting["lower_limit"] - grid_setting["grid_gap"]

    EM.run {
      ws = Faye::WebSocket::Client.new('wss://ftx.com/ws/')

      ws.on :open do |event|
        # Indicator for ws.on :open, but not Websocket connected yet
        puts console_prefix(grid_setting) + "#{status} ws open." 

        ws.send(ws_op("login"))
        ws.send(ws_op("subscribe", "orders"))

        # Real Websocket connection start with login and subscribe
        puts console_prefix(grid_setting) + "ws init ok."
      end

      ws.on :message do |event|
        valid_message = ""
        ws_message = JSON.parse(event.data)

        if ws_message["type"] == "update" && ws_message["channel"] == "orders"
          order_data = ws_message["data"]

          # 要驗證在格子上才算數
          valid_message = "normal" if order_data["market"] == market_name && order_data["status"] == "closed" && order_data["type"] == "limit" && order_data["size"] == grid_setting["order_size"]
          valid_message = "close" if order_data["price"] == close_price && order_data["size"] == grid_setting["order_size"]
        end

        unless ["normal", "close"].include?(valid_message)
          puts console_prefix(grid_setting) + ws_message.to_s
          next
        end

        case valid_message
        when "normal"
          time_stamp = Time.now.to_i - 2

          case order_data["side"]
          when "sell"
            order_price = order_data["price"] - grid_setting["grid_gap"]
            order_side = "buy"
          when "buy"
            order_price = order_data["price"] + grid_setting["grid_gap"]
            order_side = "sell"
          end
          
          payload = {market: market_name, side: order_side, price: order_price, type: "limit", size: grid_setting["order_size"]}

          order_result = FtxClient.place_order("GridOnRails", payload)
          puts console_prefix(grid_setting) + "payload: " + payload.to_s
          puts console_prefix(grid_setting) + "result: " + order_result.to_json

          sleep(0.5)
          @limit_orders = FtxClient.order_history("GridOnRails", {market: market_name, side: order_side, orderType: "limit", start_time: time_stamp})["result"]
          create_or_update_orders_status!(grid_setting, @limit_orders)
          
        when "close"
          @open_orders = FtxClient.open_orders("GridOnRails", market: market_name)["result"]

          to_cancel_order_ids = @open_orders.pluck("id")
          to_cancel_order_ids.each {|order_id| FtxClient.cancel_order("GridOnRails", order_id)}

          grid_setting.grid_orders.where(ftx_order_id: to_cancel_order_ids).update_all(status: 'closed')

          puts console_prefix(grid_setting) + "market_name: #{market_name} cancel #{to_cancel_order_ids.count} orders."
          grid_setting.update(status: "close")

          ws.close
        end
      end

      ws.on :close do |event|
        puts console_prefix(grid_setting) + "ws closed with #{event.code}"

        sleep(1)
        ws_restart(grid_setting) if event.code == 1006
        EM::stop_event_loop
      end

      EM.add_periodic_timer(58) { 
        ws.send(ws_op("ping"))
      }
    }
  end

  def grids_calc(side, market_price, grid_setting)

    upper_value, lower_value = grid_setting["upper_limit"], grid_setting["lower_limit"]
    gap_value =  grid_setting["grid_gap"]

    price_on_grid = ((market_price - lower_value) / gap_value).round(0) * gap_value + lower_value

    case side
    when "buy"
      return ((upper_value - lower_value) / gap_value).round(0) if price_on_grid >= upper_value
      return ((price_on_grid - lower_value) / gap_value).round(0) if price_on_grid > lower_value
      return 0
    when "sell"
      return ((upper_value - lower_value) / gap_value).round(0) if price_on_grid <= lower_value
      return ((upper_value - price_on_grid) / gap_value).round(0) if price_on_grid < upper_value
      return 0
    end
  end

  def bias_required_calc(grid_setting, buy_grids, sell_grids, open_orders)
    # 保留可以使用spot，先不考慮合約
    spot_in_amount = grid_setting["input_spot_amount"]
    size_value = grid_setting["order_size"]

    open_sell_grids, open_buy_grids = 0, 0
    open_orders.each do |order|
      open_sell_grids += 1 if order["side"] == "sell"
      open_buy_grids += 1 if order["side"] == "buy"
    end

    missing_sell_grids = sell_grids - open_sell_grids
    missing_buy_grids = buy_grids - open_buy_grids
    # check bias to operate
    missing_grids_bias = missing_sell_grids - missing_buy_grids

    db_open_orders = grid_setting.grid_orders.detect { |order| ["new","open"].include?(order.status) }
    if db_open_orders.nil? || db_open_orders.size == 0
      init_required_amount = missing_sell_grids * size_value
      spot_in_bias = init_required_amount - spot_in_amount

      # 需要買的數量
      if spot_in_bias > 0
        bias_required_amount = spot_in_bias
      else
        # 在新setting中更新實際使用量
        grid_setting.update(input_spot_amount: init_required_amount)
        bias_required_amount = 0
      end
    else
      bias_required_amount = missing_grids_bias * size_value
    end

    puts "missing buy_grids        = #{missing_buy_grids}"
    puts "missing sell_grids       = #{missing_sell_grids}"
    puts "missing_grids_bias       = #{missing_grids_bias}"

    puts "spot_in_amount           = #{spot_in_amount}"
    puts console_prefix(grid_setting) + "bias_required_amount     = #{bias_required_amount}"

    return bias_required_amount
  end

  def bias_required_amount_exec(grid_setting, bias_required_amount)
    market_name = grid_setting["market_name"]

    time_stamp = Time.now.to_i - 2
    order_side = bias_required_amount > 0 ? "buy" : "sell"
    bias_remained_amount = bias_required_amount
    payload_market = {market: market_name, side: order_side, price: nil, type: "market", size: nil}

    until bias_remained_amount == 0
      @market_orders = FtxClient.order_history("GridOnRails", {market: market_name, orderType: "market", start_time: time_stamp})["result"]

      executed_amount = @market_orders.sum {|order| order["filledSize"] if order["status"] == "closed" && order["side"] == order_side}
      executed_amount = 0 - executed_amount if order_side == "sell"
      puts console_prefix(grid_setting) + "executed_amount:" + executed_amount.to_s

      bias_remained_amount = bias_required_amount - executed_amount
      batch_amount = batch_amount_calc(grid_setting, bias_remained_amount)

      unless batch_amount == 0
        puts "#{order_side}ing amount            = #{batch_amount}/#{bias_remained_amount}"
        payload = payload_market.merge({size: batch_amount.abs})

        order_result = FtxClient.place_order("GridOnRails", payload)
        puts console_prefix(grid_setting) + "payload:" + payload.to_s
        puts console_prefix(grid_setting) + "result: " + order_result.to_json

        sleep(2)     
      end
    end

    return @market_orders
  end

  def gird_orders_exec(side, grid_number, market_price, grid_setting, open_orders)

    time_stamp = Time.now.to_i - 2
    market_name = grid_setting["market_name"]

    payload_limit = {market: market_name, side: side, price: nil, type: "limit", size: grid_setting["order_size"]}

    gap_value = grid_setting["grid_gap"]
    price_precision = decimals(gap_value)

    gap_value = side == "buy" ? 0 - gap_value : gap_value

    ref_price = ref_price_calc(market_price, grid_setting)

    (1..grid_number).each do |i|

      order_price = (ref_price + gap_value * i).round(price_precision)

      next if open_orders.detect {|order| order["price"].round(price_precision) == order_price}

      payload = payload_limit.merge({price: order_price})

      order_result = FtxClient.place_order("GridOnRails", payload)
      sleep(0.15)

      puts "payload(#{side}) :" + payload.to_s
      puts "order result:" + order_result.to_json
    end

    sleep(0.5)
    @limit_orders = FtxClient.order_history("GridOnRails", {market: market_name, side: side, orderType: "limit", start_time: time_stamp})["result"]

    return @limit_orders
  end

  def ref_price_calc(market_price, grid_setting)

    upper_value, lower_value = grid_setting["upper_limit"], grid_setting["lower_limit"]
    gap_value =  grid_setting["grid_gap"]

    price_on_grid = ((market_price - lower_value) / gap_value).round(0) * gap_value + lower_value

    return upper_value if price_on_grid >= upper_value
    return lower_value if price_on_grid <= lower_value
    return price_on_grid
  end

  def batch_amount_calc(grid_setting, target_amount)
    size_step = grid_setting["size_step"]

    return 0 if target_amount == 0

    side_name = target_amount > 0 ? "asks" : "bids"

    orderbook = FtxClient.orderbook(grid_setting["market_name"] ,:depth => 1)["result"]

    batch_size_limit = ((orderbook[side_name][0][1] / 1.618) / size_step).round(0) * size_step
    batch_size_limit = 0 - batch_size_limit if target_amount < 0

    batch_amount = target_amount.abs >= batch_size_limit.abs ? batch_size_limit : target_amount

    return batch_amount
  end

  def create_or_update_orders_status!(grid_setting, ftx_orders)
    result = {created: 0, updated: 0}
    return result if ftx_orders.nil?

    ftx_order_ids = ftx_orders.pluck("id")
    db_orders = grid_setting.grid_orders.where(ftx_order_id: ftx_order_ids)
    db_order_ids = db_orders.pluck(:ftx_order_id).map(&:to_i)

    ftx_orders.each do |order|
      if db_order_ids.include?(order["id"])
        db_order = db_orders.detect {|db_order| db_order["ftx_order_id"] == order["id"]}
        result[:updated] += 1
      else
        db_order = GridOrder.new(
          "market_name"=> order["market"],
          "grid_setting_id" => grid_setting["id"],
          "ftx_order_id" => order["id"]
        )
        result[:created] += 1
      end

      db_order.attributes = {
        "order_type"=> order["type"],
        "side"=> order["side"],
        "price"=> order["price"],
        "size"=> order["size"],
        "status"=> order["status"],
        "filledSize"=> order["filledSize"],
        "remainingSize"=> order["remainingSize"],
        "avgFillPrice"=> order["avgFillPrice"],
        "createdAt"=> order["createdAt"]}

      db_order.save
    end
    return result
  end

  def decimals(a)
    num = 0
    while(a != a.to_i)
        num += 1
        a *= 10
    end
    num   
  end

  def console_prefix(grid_setting)
    return "#{Time.now.strftime('%H:%M:%S')}: grid_setting_id: #{grid_setting.id}: "
  end
end
