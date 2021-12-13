class GridExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(grid_setting_id)

    @grid_setting = GridSetting.includes(:grid_orders).find(grid_setting_id)
    puts console_prefix(@grid_setting) + "sidekiq GridExecutorJob starting..."
    return unless params_check(@grid_setting)

    grid_orders_init!(@grid_setting)
    @grid_setting.update(:status => "active")
    puts console_prefix(@grid_setting) + "Grid Orders initialized, ready for main loop."

    # main loop
    ws_start(@grid_setting)

    puts console_prefix(@grid_setting) + "sidekiq GridExecutorJob on market_name: #{@grid_setting["market_name"]} closed, See You!"
  end

  def params_check(grid_setting)
    return false unless ["active", "new"].include?(grid_setting["status"])
    
    check_value = {}
    upper_limit, lower_limit = grid_setting["upper_limit"], grid_setting["lower_limit"]
    grids, grid_gap = grid_setting["grids"], grid_setting["grid_gap"]
    price_step = grid_setting["price_step"]

    puts console_prefix(grid_setting) + "setting market_name      = #{grid_setting["market_name"]}"
    puts console_prefix(grid_setting) + "setting upper_limit      = #{upper_limit}"
    puts console_prefix(grid_setting) + "setting lower_limit      = #{lower_limit}"
    puts console_prefix(grid_setting) + "setting grids            = #{grids}"
    puts console_prefix(grid_setting) + "setting grid_gap         = #{grid_gap}"
    puts console_prefix(grid_setting) + "setting price_step       = #{price_step}"

    check_value["grids"] = ((upper_limit - lower_limit) / price_step + 1)
    check_value["grid_gap"] = (((upper_limit - lower_limit) / price_step) / (grids - 1)).round(0) * price_step
    check_value["upper_limit"] = lower_limit + ((grids - 1) * grid_gap)

    ["grids","grid_gap","upper_limit"].each do |item|
      compare_sym = ""
      case item
      when "grids"
        compare_sym = ">" if grid_setting[item] > check_value[item]
      else
        compare_sym = "!=" if grid_setting[item] != check_value[item]
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
    upper_value, lower_value = grid_setting["upper_limit"], grid_setting["lower_limit"]
    gap_value, size_value = grid_setting["grid_gap"], grid_setting["order_size"]

    # 保留可以使用spot，先不考慮合約
    db_i, ftx_i = 0, 0
    missing_grids = {"sell" => [] , "buy" => []}
    order_id = {db: ""}
    to_save_orders = []

    db_orders = grid_setting.grid_orders.where(status: ["new","open"]).order(price: :asc, ftx_order_id: :asc)
    db_i_max = db_orders.size - 1

    ftx_orders = FtxClient.open_orders("GridOnRails", market: market_name)["result"].select {|o| o["createdAt"] > grid_setting.created_at}.sort_by!{ |o| [o["price"],o["createdAt"]] }
    ftx_i_max = ftx_orders.size - 1

    @market = FtxClient.market_info(market_name)["result"]

    market_price_on_grid = ((@market["price"] - lower_value) / gap_value).round(0) * gap_value + lower_value

    # 檢查重複出現的單子
    last_price = 0
    to_cancel_order_ids = []
    ftx_orders.each do |order|
      cur_price = order["price"]
      if last_price == cur_price
        puts console_prefix(grid_setting) + "Canceling FTX duplicated grid order...#{order["id"]}"
        to_cancel_order_ids << order["id"]
        ftx_orders.delete(order)
        ftx_i_max -= 1
        next
      end
      # market_price_on_grid calibration for missleading price
      # in case market_price is very close to next grid, but not trigger placed order yet, will be wrong price_on_grid.
      market_price_on_grid += @market["price"] > market_price_on_grid ? gap_value : - gap_value if cur_price == market_price_on_grid
      last_price = cur_price
    end

    unless to_cancel_order_ids == []
      to_cancel_order_ids.each {|order_id| FtxClient.cancel_order("GridOnRails", order_id)}
      grid_setting.grid_orders.where(ftx_order_id: to_cancel_order_ids).update_all(status: 'canceled')
      puts console_prefix(grid_setting) + "Total #{to_cancel_order_ids.count} orders canceled OK. Updated status to canceled."
    end

    (lower_value..upper_value).step(gap_value).each do |grid_price|
      order_id[:db] = db_orders[db_i] ? db_orders[db_i].ftx_order_id.to_i : 0
      db_price = db_orders[db_i] ? (db_orders[db_i].price / grid_setting["price_step"]).round(0) * grid_setting["price_step"] : 0
      ftx_price = ftx_orders[ftx_i] ? (ftx_orders[ftx_i]["price"] / grid_setting["price_step"]).round(0) * grid_setting["price_step"] : 0

      if grid_price == market_price_on_grid
        if db_price == market_price_on_grid
          to_save_orders << FtxClient.orders("GridOnRails", order_id[:db])["result"]
          puts console_prefix(grid_setting) + "#{grid_price}:  db_i: #{db_i}, #{db_price}  ftx_i: #{ftx_i}, #{ftx_price}"
          db_i += 1
        end

        if ftx_price == market_price_on_grid
          puts console_prefix(grid_setting) + "#{grid_price}:  db_i: #{db_i}, #{db_price}  ftx_i: #{ftx_i}, #{ftx_price}"
          ftx_i += 1 
        end
        next 
      end

      while db_i + 1 <= db_i_max ? (db_orders[db_i].price == db_orders[db_i + 1].price) : false
        to_save_orders << FtxClient.orders("GridOnRails", order_id[:db])["result"]
        puts console_prefix(grid_setting) + "#{grid_price}:  db_i: #{db_i}, #{db_price}"
        db_i += 1
        order_id[:db] = db_orders[db_i].ftx_order_id.to_i
      end

      grid_side = market_price_on_grid > grid_price ? "buy" : "sell"

      if ftx_price != grid_price
        missing_grids[grid_side] << grid_price
        to_save_orders << FtxClient.orders("GridOnRails", order_id[:db])["result"] if db_price == grid_price
        puts console_prefix(grid_setting) + "#{grid_price}:  db_i: #{db_i}, #{db_price}  ftx_i: #{ftx_i}, #{ftx_price}"
        db_i -= 1 if db_price != grid_price
        ftx_i -= 1
      elsif ftx_price == grid_price
        unless order_id[:db] == ftx_orders[ftx_i]["id"]
          to_save_orders << ftx_orders[ftx_i]
          to_save_orders << FtxClient.orders("GridOnRails", order_id[:db])["result"] if db_price == grid_price
          puts console_prefix(grid_setting) + "#{grid_price}:  db_i: #{db_i}, #{db_price}  ftx_i: #{ftx_i}, #{ftx_price}"
          db_i -= 1 if db_price != grid_price
        end
      end
      # puts "db_i #{db_i} #{db_price}   ftx_i #{ftx_i} #{ftx_price}  grid_price #{grid_price}"
      db_i += 1
      ftx_i += 1
    end

    unless to_save_orders == []
      puts console_prefix(grid_setting) + "market_price_on_grid     = #{market_price_on_grid}"
      puts console_prefix(grid_setting) + "orders: to_save_orders   = " + create_or_update_orders_status!(grid_setting, to_save_orders).to_s
    end

    return if missing_grids["sell"].size == 0 && missing_grids["buy"].size == 0
    
    # 2. missing(init) buy/sell amounts caculation
    bias_required_amount = bias_required_calc(grid_setting, missing_grids)

    # 3. Update orders informations from ftx after bias_required_amount_exec orders
    @market_orders = bias_required_amount_exec(grid_setting, bias_required_amount)
    puts console_prefix(grid_setting) + "orders: bias_amount      = " + create_or_update_orders_status!(grid_setting, @market_orders).to_s

    # 4. Place buy/sell grid orders and Update orders informations from ftx after place orders
    @grids_orders = gird_orders_exec(grid_setting, missing_grids)
    puts console_prefix(grid_setting) + "orders: gird_orders_exec = " + create_or_update_orders_status!(grid_setting, @grids_orders).to_s
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
    puts console_prefix(grid_setting) + "WebSocket restarting..."
    grid_orders_init!(grid_setting)
    puts console_prefix(grid_setting) + "Grid Orders initialized for restart, ready for main loop."
    ws_start(grid_setting)
  end

  def ws_start(grid_setting)
    active_grid_setting_market_names = GridSetting.where(status: "active").pluck(:market_name)

    market_name = grid_setting["market_name"]
    close_price = grid_setting["id"] * grid_setting["price_step"]
    grid_orders_init_executing = false
    ws_datas = []

    EM.run {
      ws = Faye::WebSocket::Client.new('wss://ftx.com/ws/')

      ws.on :open do |event|
        # Indicator for ws.on :open, but not Websocket connected yet
        ws.send(ws_op("login"))
        ws.send(ws_op("subscribe", "orders"))

        # Real Websocket connection start with login and subscribe
        puts console_prefix(grid_setting) + "WebSocket to: wss://ftx.com/ws/"
      end

      ws.on :message do |event|
        valid_message = ""
        ws_message = JSON.parse(event.data)

        if ws_message["type"] == "update" && ws_message["channel"] == "orders"
          order_data = ws_message["data"]

          if order_data["market"] == market_name && order_data["type"] == "limit" && order_data["size"] == grid_setting["order_size"]
            valid_message = "close_grid" if order_data["price"] == close_price && order_data["status"] == "new"
            
            if is_on_grid(grid_setting, order_data["price"])
              ws_datas << order_data
              valid_message = "new_grid" if order_data["status"] == "new"
              valid_message = "normal" if order_data["status"] == "closed"
            end
          elsif active_grid_setting_market_names.include?(order_data["market"])
            valid_message = "active_ignore"
          end
        end

        unless ["normal", "close_grid", "new_grid", "active_ignore"].include?(valid_message)
          # warning line: hide ws message from ws.send(ws_op("ping"))
          # (when amounts of valid_messages were displayed, there's no need to display result of ws.send(ws_op("ping")))
          next if ws_message["type"] == "pong"
          puts console_prefix(grid_setting) + ws_message.to_s
          next
        end

        case valid_message
        when "normal"
          case order_data["side"]
          when "sell"
            order_price = order_data["price"] - grid_setting["grid_gap"]
            order_side = "buy"
          when "buy"
            order_price = order_data["price"] + grid_setting["grid_gap"]
            order_side = "sell"
          end
          
          payload = {market: market_name, side: order_side, price: order_price, type: "limit", size: grid_setting["order_size"]}
          order_result = FtxClient.place_order("GridOnRails", payload)["result"]
          
          # FTX API葛闢的時候order_result會是nil
          if order_result
            puts console_prefix(grid_setting) + "New Order: " + order_result_to_output(order_result)
          else
            if grid_orders_init_executing
              puts console_prefix(grid_setting) + "FTX API no return after place_order, grid_orders_init! executing."
            else
              grid_orders_init_executing = true
              puts console_prefix(grid_setting) + "FTX API no return after place_order, starting grid_orders_init!"
              sleep(5)
              grid_orders_init!(grid_setting)
              grid_orders_init_executing = false
              puts console_prefix(grid_setting) + "grid_orders_init! executed ok."
            end
          end
        when "close_grid"
          puts console_prefix(grid_setting) + "Now Closing..."
          # 不支援相同market多筆開單
          @open_orders = FtxClient.open_orders("GridOnRails", market: market_name)["result"].select {|order| order["createdAt"] > grid_setting.created_at}

          puts console_prefix(grid_setting) + "Canceling FTX grid orders..."
          to_cancel_order_ids = @open_orders.pluck("id")
          to_cancel_order_ids.each {|order_id| FtxClient.cancel_order("GridOnRails", order_id)}

          grid_setting.grid_orders.where(ftx_order_id: to_cancel_order_ids).update_all(status: 'canceled')
          puts console_prefix(grid_setting) + "Total #{to_cancel_order_ids.count} orders canceled OK. Updated status to canceled."

          grid_setting.update(status: "closed")
          puts console_prefix(grid_setting) + "Updated db status to canceled."

          ws.close
        end
      end

      ws.on :close do |event|
        puts console_prefix(grid_setting) + "WebSocket on close with event code: #{event.code}"

        sleep(1)
        unless grid_setting["status"] == "closed"
          ws_restart(grid_setting)
        else
          EM::stop_event_loop
        end
      end

      EM.add_periodic_timer(58) { 
        ws_orders = ws_datas.dup
        ws_datas -= ws_orders

        filtered_orders = {}
        ws_orders.each {|order| filtered_orders[order["id"]] = order}
        valid_orders = filtered_orders.map { |key, value| value }

        orders_status = create_or_update_orders_status!(grid_setting, valid_orders).to_s
        puts console_prefix(grid_setting) + "orders_status in past 58s= " + orders_status unless orders_status == "{:created=>0, :updated=>0}"
                
        ws.send(ws_op("ping"))
        # 放一起免得打架
        grid_orders_init!(grid_setting) if Time.now.to_i % 60 == 0 unless grid_setting["status"] == "closed"
      }
    }
  end

  def bias_required_calc(grid_setting, missing_grids)
    market_name = grid_setting["market_name"]

    size_value, size_step =  grid_setting["order_size"], grid_setting["size_step"]
    spot_in_amount = grid_setting["input_spot_amount"]

    # check bias to operate
    missing_grids_bias = missing_grids["sell"].size - missing_grids["buy"].size

    if grid_setting["status"] == "new"
      init_required_amount = missing_grids["sell"].size * size_value
      spot_in_bias = init_required_amount - spot_in_amount

        # 需要買的數量
      if spot_in_bias >= 0
        bias_required_amount = spot_in_bias
      else
        # 在新setting中更新實際使用量
        grid_setting.update(input_spot_amount: init_required_amount)
        bias_required_amount = 0
      end
    else
      bias_required_amount = missing_grids_bias * size_value
      usd_required_amount = missing_grids["buy"].sum * size_value

      unless bias_required_amount == 0
        target_name = market_name.split("/")[0]
        usd_available, spot_available, market_price = 0, 0, 0

        FtxClient.wallet_balances("GridOnRails")["result"].each do |balance| 
          usd_available = balance["free"] if balance["coin"] == "USD"
          if balance["coin"] == target_name
            spot_available = (balance["free"] / size_value).round(0) * size_value
            market_price = balance["usdValue"] / balance["total"]
          end
        end

        if bias_required_amount > 0
          bias_required_amount -= bias_required_amount >= spot_available ? spot_available : bias_required_amount
        else
          if usd_required_amount > usd_available
            (size_step..spot_available).step(size_step).each do |sell_amount|
              bias_required_amount = -sell_amount if sell_amount * market_price + usd_available >= usd_required_amount
            end
          else
            bias_required_amount = 0
          end
        end
      end
    end

    puts console_prefix(grid_setting) + "missing buy_grids        = #{missing_grids["buy"].size}: #{missing_grids["buy"]}"
    puts console_prefix(grid_setting) + "missing sell_grids       = #{missing_grids["sell"].size}: #{missing_grids["sell"]}"
    puts console_prefix(grid_setting) + "missing_grids_bias       = #{missing_grids_bias}"

    puts console_prefix(grid_setting) + "spot_in_amount           = #{spot_in_amount}"
    puts console_prefix(grid_setting) + "bias_required_amount     = #{bias_required_amount}"

    return bias_required_amount
  end

  def bias_required_amount_exec(grid_setting, bias_required_amount)
    market_name = grid_setting["market_name"]
    size_step = grid_setting["size_step"]

    time_stamp = Time.now.to_i - 2
    order_side = bias_required_amount > 0 ? "buy" : "sell"
    bias_remained_amount = bias_required_amount
    payload_market = {market: market_name, side: order_side, price: nil, type: "market", size: nil}

    last = {executed_amount: 0, batch_amount: 0, bias_remained_amount: 0}

    dead_loop = 0

    until bias_remained_amount == 0
      @market_orders = FtxClient.order_history("GridOnRails", {market: market_name, orderType: "market", start_time: time_stamp})["result"]

      executed_amount = @market_orders.sum {|order| order["filledSize"] if order["status"] == "closed" && order["side"] == order_side}
      executed_amount = 0 - executed_amount if order_side == "sell"

      puts console_prefix(grid_setting) + "executed_amount          = " + executed_amount.to_s

      bias_remained_amount = ((bias_required_amount - executed_amount) / size_step).round(0) * size_step
      batch_amount = batch_amount_calc(grid_setting, bias_remained_amount)

      unless batch_amount == 0
        puts console_prefix(grid_setting) + "#{order_side}ing amount            = #{batch_amount}/#{bias_remained_amount}"
        payload = payload_market.merge({size: batch_amount.abs})

        order_result = FtxClient.place_order("GridOnRails", payload)["result"]
        puts console_prefix(grid_setting) + "payload:" + payload.to_s
        puts console_prefix(grid_setting) + "result: " + order_result_to_output(order_result)

        dead_loop += last[:executed_amount] == executed_amount && last[:batch_amount] == batch_amount && last[:bias_remained_amount] == bias_remained_amount ? 1 : -dead_loop

        last[:executed_amount] = executed_amount
        last[:batch_amount] = batch_amount
        last[:bias_remained_amount] = bias_remained_amount

        sleep(2)     
      end

      if dead_loop >=3
        puts console_prefix(grid_setting) + "quit bias_required_amount_exec: dead_loop"
        # 回傳已執行
        return @market_orders
      end
    end
    # 需filter未執行的
    return @market_orders
  end

  def gird_orders_exec(grid_setting, missing_grids)
    time_stamp = Time.now.to_i - 2
    market_name = grid_setting["market_name"]
    
    missing_grids.each do |side, price_arr| 
      payload_limit = {market: market_name, side: side, price: nil, type: "limit", size: grid_setting["order_size"]}

      price_arr.each do |price|
        payload = payload_limit.merge({price: price})
        order_result = FtxClient.place_order("GridOnRails", payload)["result"]

        puts console_prefix(grid_setting) + "payload(#{side}) :" + payload.to_s
        puts console_prefix(grid_setting) + "result:" + order_result_to_output(order_result)
      end
    end
    # 感覺好像回傳會少，多等一下下好了
    sleep(1)
    response = FtxClient.order_history("GridOnRails", {market: market_name, orderType: "limit", start_time: time_stamp})
    @limit_orders = response["result"]

    while response["hasMoreData"]
      end_time_stamp = response["result"].last["createdAt"].to_time.to_i
      response = FtxClient.order_history("GridOnRails", {market: market_name, orderType: "limit", start_time: time_stamp, end_time: end_time_stamp})
      @limit_orders += response["result"]
    end

    @limit_orders.each {|o| o["status"] = "new"} unless grid_setting["status"] == "new"

    return @limit_orders
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
    
    new_orders_tbu = []
    existed_orders_tbu = []
    
    ftx_orders.each do |order|
      if db_order_ids.include?(order["id"])
        db_order = db_orders.detect {|db_order| db_order["ftx_order_id"] == order["id"]}
        db_order.attributes = to_update_attributes(order)

        existed_orders_tbu << db_order.attributes
        result[:updated] += 1
      else
        db_order = GridOrder.new(
          "market_name"=> order["market"],
          "grid_setting_id" => grid_setting["id"],
          "ftx_order_id" => order["id"],
          "created_at" => DateTime.now,
          "updated_at" => DateTime.now)
        db_order.attributes = to_update_attributes(order)

        new_orders_tbu << db_order.attributes.except!("id")
        result[:created] += 1
      end
    end

    GridOrder.upsert_all(new_orders_tbu) unless new_orders_tbu.empty?
    GridOrder.upsert_all(existed_orders_tbu) unless existed_orders_tbu.empty?

    return result
  end

  def to_update_attributes(order)
    return {"order_type"=> order["type"],
            "side"=> order["side"],
            "price"=> order["price"],
            "size"=> order["size"],
            "status"=> order["status"],
            "filledSize"=> order["filledSize"],
            "remainingSize"=> order["remainingSize"],
            "avgFillPrice"=> order["avgFillPrice"],
            "createdAt"=> order["createdAt"]}
  end

  def is_on_grid(grid_setting, price)
    upper_value, lower_value = grid_setting["upper_limit"], grid_setting["lower_limit"]
    return false if price == upper_value || price == lower_value 
    gap_value = grid_setting["grid_gap"]

    price_above_lower_value = ((price - lower_value) / grid_setting["price_step"]).round(0) * grid_setting["price_step"]

    on_grid = price.between?(lower_value, upper_value) && price_above_lower_value % gap_value == 0

    unless on_grid
      puts console_prefix(grid_setting) + "Not on grid price: #{price}, lower_value: #{lower_value}, gap_value: #{gap_value}"
      puts console_prefix(grid_setting) + "price_above_lower_value: #{price_above_lower_value}, price_above_lower_value % gap_value: #{price_above_lower_value % gap_value}"
    end
    return on_grid
  end

  def console_prefix(grid_setting)
    return "#{Time.now.strftime('%H:%M:%S')}: grid_setting_id: #{grid_setting.id}: "
  end

  def order_result_to_output(order_result)
    if order_result
      order_result.select {|k,v| {k => v} if ["market","type","side","price","size"].include?(k)}.to_s
    else
      return "order_result is nil"
    end
  end
end
