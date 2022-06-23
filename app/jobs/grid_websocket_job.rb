class GridWebsocketJob < ApplicationJob
  queue_as :default

  def logger
    Logger.new('log/grid_websocket_job.log')
  end

  def perform(sub_account_id)

    # single_sub_account
    case get_ws_state(sub_account_id)
    when "connected"
      return
    when "connecting"
      @sub_account = SubAccount.find_by_id(sub_account_id)
      ws_start
      return
    end

    # all sub_accounts
    if Redis.new.get("sub_account:grids:ws_state") == "connecting"
      @sub_account = SubAccount.find_by_id(sub_account_id)
      grids_init_and_ws_start
    else
      logger.info("Grids") {"Reset all sockets"}
      reset_ws_states

      Redis.new.set("sub_account:grids:ws_state", "connecting")

      sub_account_ids = SubAccount.where(application: "grid").pluck(:id)
      sub_account_ids.each {|id| Thread.new{ GridWebsocketJob.perform_later(id) }}

      last_ws_state = get_ws_state(sub_account_ids.last)

      while last_ws_state != "connected"
        sleep(1)
        last_ws_state = get_ws_state(sub_account_ids.last)
      end

      Redis.new.del("sub_account:grids:ws_state")
    end
  end

  def ws_op(op_name, channel = "")
    case op_name
    when "login"
      ts = DateTime.now.strftime('%Q')

      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        @sub_account.crypt.decrypt_and_verify(@sub_account[:encrypted_secret_key]), 
        ts + "websocket_login")
  
      login_op = {
        op: "login",
        args: {
          key: @sub_account.crypt.decrypt_and_verify(@sub_account[:encrypted_public_key]),
          sign: signature,
          time: ts.to_i,
          subaccount: @sub_account.name}}.to_json

      return login_op
    when "subscribe"
      return { op: "subscribe", channel: channel}.to_json
    when "ping"
      return { op: "ping"}.to_json
    end
  end

  def ws_restart
    logger.warn(@sub_account.id) {"WebSocket restarting..."}
    grids_init_and_ws_start
  end

  def grids_init_and_ws_start
    GridInitJob.perform_later(@sub_account.id)
    ws_start
  end

  def ws_start
    EM.run {
      ws = Faye::WebSocket::Client.new('wss://ftx.com/ws/')

      ws.on :open do |event|
        ws.send(ws_op("login"))
        ws.send(ws_op("subscribe", "orders"))
      end

      ws.on :message do |event|
        ws_message = JSON.parse(event.data)
        next if ws_message["type"] == "pong"
        next set_ws_state(@sub_account.id, "connected") if ws_message["type"] == "subscribed"

        logger.info(@sub_account.id) {ws_message.to_s}
        ws_message_handler(ws_message)
      end

      ws.on :close do |event|
        del_ws_state(@sub_account.id, "WebSocket on close with event code: #{event.code}")
        ws_restart
      end

      EM.add_periodic_timer(58) { 
        ws.send(ws_op("ping"))
        # 放一起免得打架
        GridInitJob.perform_later(@sub_account.id) if Time.now.to_i % 60 == 0 
      }
    }
  end
  
  def ws_message_handler(ws_message)
    return unless ws_message["type"] == "update" && ws_message["channel"] == "orders"

    order_data = ws_message["data"]
    market_name = order_data["market"]
    grid_setting = get_current_grid_setting(market_name)

    return unless grid_setting
    return unless order_data["type"].to_s == "limit" && order_data["size"].to_s == grid_setting["order_size"].to_s && grid_setting["status"].to_s == "active"

    return unless is_on_grid(grid_setting, order_data["price"])

    save_ftx_order(grid_setting, order_data)

    if order_data["status"] == "closed"
      case order_data["side"]
      when "sell"
        order_price = order_data["price"] - grid_setting["grid_gap"]
        order_side = "buy"
      when "buy"
        order_price = order_data["price"] + grid_setting["grid_gap"]
        order_side = "sell"
      end
      
      payload = {market: market_name, side: order_side, price: order_price, type: "limit", size: grid_setting["order_size"]}
      order_result = FtxClient.place_order(@sub_account, payload)["result"]
      
      # FTX API葛闢的時候order_result會是nil
      if order_result
        logger.info(@sub_account.id) {"New Order: " + order_result_to_output(order_result)}
      else
        logger.warn(@sub_account.id) {"FTX API no return after place_order, starting grid_init"}
        sleep(5)
        GridInitJob.perform_later(@sub_account.id)
      end
    end
  end

  def is_on_grid(grid_setting, price)
    upper_value, lower_value = grid_setting["upper_limit"], grid_setting["lower_limit"]
    return false if price == upper_value || price == lower_value 
    gap_value = grid_setting["grid_gap"]

    price_above_lower_value = ((price - lower_value) / grid_setting["price_step"]).round(0) * grid_setting["price_step"]

    on_grid = price.between?(lower_value, upper_value) && price_above_lower_value % gap_value == 0

    return on_grid
  end

  def save_ftx_order(grid_setting, order)
    db_order = GridOrder.find_by(ftx_order_id: order["id"])

    db_order = GridOrder.new(
      "user_id" => grid_setting["user_id"],
      "market_name"=> order["market"],
      "grid_setting_id" => grid_setting["id"],
      "ftx_order_id" => order["id"],
      "created_at" => DateTime.now,
      "updated_at" => DateTime.now) unless db_order
    db_order.attributes = attributes_from_ftx_to_db(order)
    db_order.save
  end

  def get_current_grid_setting(market_name)
    current_grid_settings = Redis.new.keys "sub_account\:#{@sub_account.id}\:grid_setting\:[0-9]*"
    return nil if current_grid_settings.empty?
    (Redis.new.mget current_grid_settings).each do |redis_data|
      grid_setting = JSON.parse(redis_data)
      if grid_setting["market_name"] == market_name
        grid_setting.each do |k,v|
          if ["lower_limit", "upper_limit", "grid_gap", 
            "input_USD_amount", "input_spot_amount", "input_totalUSD_amount", 
            "trigger_price", "threshold", "order_size", "price_step", "size_step"].include?(k) 
            grid_setting[k] = v.to_f if v
          end
        end
        return grid_setting
      end
    end
    return nil
  end

  def get_ws_state(sub_account_id)
    Redis.new.get("sub_account:#{sub_account_id}:ws_state")
  end

  def set_ws_state(sub_account_id, state = "")
    Redis.new.set("sub_account:#{sub_account_id}:ws_state", state)
    logger.info(sub_account_id) {state}
  end

  def del_ws_state(sub_account_id, msg = "")
    Redis.new.del("sub_account:#{sub_account_id}:ws_state")
    logger.info(sub_account_id) {msg}
  end

  def reset_ws_states
    current_keys = Redis.new.keys "sub_account\:[0-9]*\:ws_state"
    Redis.new.del(*current_keys)
  end
end