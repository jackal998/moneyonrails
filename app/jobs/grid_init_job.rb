class GridInitJob < ApplicationJob
  queue_as :default

  def logger
    Logger.new('log/grid_init_job.log')
  end

  def perform(sub_account_id)
    @sub_account = SubAccount.find_by_id(sub_account_id)
    return unless @sub_account
    @user = @sub_account.user
    @grid_settings = @user.grid_settings.includes(:grid_orders).where(status: ["active", "new"])

    @grid_settings.map {|gs| [gs.id, grid_orders_init!(gs)]}.each {|gs_id, init_result| logger.info(gs_id) {init_result}}
  end

  def grid_orders_init!(grid_setting)
    @grid_setting = grid_setting

    return if get_grid_state(@grid_setting.id, "init_state") == "processing"
    set_grid_state(@grid_setting.id, "processing", "init_state")
    logger.info(@grid_setting.id) {"========== Init Start ======="}

    # 1. remove duplicated ftx orders and calc market_price_on_grid
    ftx_orders, market_price_on_grid = ftx_dup_orders_and_market_price_on_grid_check
    logger.info(@grid_setting.id) {"market_price_on_grid     = #{market_price_on_grid}"}
    
    # 2. checking if any missing grids
    missing_grids = grid_orders_missing?(ftx_orders, market_price_on_grid)
    return "nothing to update." if missing_grids["sell"].size == 0 && missing_grids["buy"].size == 0

    # 3. missing(init) buy/sell amounts caculation
    bias_required_amount = bias_required_calc(missing_grids)

    # 4. Update orders informations from ftx after bias_required_amount_exec orders
    market_orders = bias_required_amount_exec(bias_required_amount)
    logger.info(@grid_setting.id) {"orders: bias_amount      = " + create_or_update_orders_status!(market_orders).to_s}

    # 5. Place buy/sell grid orders and Update orders informations from ftx after place orders
    grids_orders = gird_orders_exec(missing_grids)
    logger.info(@grid_setting.id) {"orders: gird_orders_exec = " + create_or_update_orders_status!(grids_orders).to_s}

    @grid_setting.update(:status => "active") if @grid_setting.status != "active"

    # 6. Register grid_setting to redis
    set_grid_state(@grid_setting.id, @grid_setting.to_json)
    set_grid_state(@grid_setting.id, "done", "init_state")
    return "========== Init OK =========="
  end

  def ftx_dup_orders_and_market_price_on_grid_check
    market_name = @grid_setting["market_name"]
    lower_value, gap_value = @grid_setting["lower_limit"], @grid_setting["grid_gap"]

    market_info = FtxClient.market_info(market_name)["result"]
    ftx_orders = FtxClient.open_orders(@sub_account, market: market_name)["result"].select {|o| o["createdAt"] > @grid_setting.created_at}.sort_by!{ |o| [o["price"],o["createdAt"]]}

    market_price_on_grid = ((market_info["price"] - lower_value) / gap_value).round(0) * gap_value + lower_value

    last_price = 0
    to_cancel_order_ids = []
    ftx_orders.each do |order|
      cur_price = order["price"]
      # market_price_on_grid calibration for missleading price
      # in case market_price is very close to next grid, but not trigger placed order yet, will be wrong price_on_grid.
      market_price_on_grid += market_info["price"] > market_price_on_grid ? gap_value : - gap_value if cur_price == market_price_on_grid

      if last_price == cur_price
        to_cancel_order_ids << order["id"]
        ftx_orders.delete(order)
        next
      end
      last_price = cur_price
    end

    unless to_cancel_order_ids == []
      to_cancel_order_ids.each {|order_id| FtxClient.cancel_order(@sub_account, order_id)}
      @grid_setting.grid_orders.where(ftx_order_id: to_cancel_order_ids).update_all(status: 'canceled')
      logger.info(@grid_setting.id) {"Total #{to_cancel_order_ids.count} FTX duplicated orders canceled and change status to canceled."}
    end
    return [ftx_orders, market_price_on_grid]
  end

  def grid_orders_missing?(ftx_orders, market_price_on_grid)
    db_i, ftx_i = 0, 0
    to_save_orders = []
    missing_grids = {"sell" => [] , "buy" => []}

    upper_value, lower_value = @grid_setting["upper_limit"], @grid_setting["lower_limit"]
    gap_value, size_value = @grid_setting["grid_gap"], @grid_setting["order_size"]
    price_step = @grid_setting["price_step"]

    db_orders = @grid_setting.grid_orders.where(status: ["new","open"]).order(price: :asc, ftx_order_id: :asc)
    db_i_max = db_orders.size - 1

    (lower_value..upper_value).step(gap_value).each do |grid_price|
      db_ftx_order_id = db_orders[db_i] ? db_orders[db_i].ftx_order_id.to_i : 0
      db_price = db_orders[db_i] ? (db_orders[db_i].price / price_step).round(0) * price_step : 0
      ftx_price = ftx_orders[ftx_i] ? (ftx_orders[ftx_i]["price"] / price_step).round(0) * price_step : 0

      if grid_price == market_price_on_grid
        grid_orders_info_for_debug = "#{grid_price}:  db_i: #{db_i}, #{db_price}  ftx_i: #{ftx_i}, #{ftx_price}"

        if db_price == market_price_on_grid
          to_save_orders << FtxClient.orders(@sub_account, db_ftx_order_id)["result"]
          logger.warn(@grid_setting.id) {"grid_price for debug     = #{grid_orders_info_for_debug}"}
          db_i += 1
        end

        if ftx_price == market_price_on_grid
          logger.warn(@grid_setting.id) {"grid_price for debug     = #{grid_orders_info_for_debug}"}
          ftx_i += 1 
        end
        next 
      end

      while db_i + 1 <= db_i_max ? (db_orders[db_i].price == db_orders[db_i + 1].price) : false
        to_save_orders << FtxClient.orders(@sub_account, db_ftx_order_id)["result"]
        logger.warn(@grid_setting.id) {"grid_price for debug     = #{grid_price}:  db_i: #{db_i}, #{db_price}"}
        db_i += 1
        db_ftx_order_id = db_orders[db_i].ftx_order_id.to_i
      end

      grid_orders_info_for_debug = "#{grid_price}:  db_i: #{db_i}, #{db_price}  ftx_i: #{ftx_i}, #{ftx_price}"
      grid_side = market_price_on_grid > grid_price ? "buy" : "sell"

      if ftx_price != grid_price
        missing_grids[grid_side] << grid_price
        to_save_orders << FtxClient.orders(@sub_account, db_ftx_order_id)["result"] if db_price == grid_price
        logger.warn(@grid_setting.id) {"grid_price for debug     = #{grid_orders_info_for_debug}"}
        db_i -= 1 if db_price != grid_price
        ftx_i -= 1
      elsif ftx_price == grid_price
        unless db_ftx_order_id == ftx_orders[ftx_i]["id"]
          to_save_orders << ftx_orders[ftx_i]
          to_save_orders << FtxClient.orders(@sub_account, db_ftx_order_id)["result"] if db_price == grid_price
          logger.warn(@grid_setting.id) {"grid_price for debug     = #{grid_orders_info_for_debug}"}
          db_i -= 1 if db_price != grid_price
        end
      end
      db_i += 1
      ftx_i += 1
    end
    # for nil result from ftx if order is canceled
    to_save_orders.compact!
    logger.info(@grid_setting.id) {"orders: to_save_orders   = " + create_or_update_orders_status!(to_save_orders).to_s} unless to_save_orders == []
    return missing_grids
  end

  def gird_orders_exec(missing_grids)
    time_stamp = Time.now.to_i - 2
    market_name = @grid_setting["market_name"]
    
    missing_grids.each do |side, price_arr| 
      payload_limit = {market: market_name, side: side, price: nil, type: "limit", size: @grid_setting["order_size"]}

      price_arr.each do |price|
        payload = payload_limit.merge({price: price})
        order_result = FtxClient.place_order(@sub_account, payload)["result"]

        logger.info(@grid_setting.id) {"payload                  = " + payload.to_s}
        logger.info(@grid_setting.id) {"result                   = " + order_result_to_output(order_result)}
      end
    end
    # 感覺好像回傳會少，多等一下下好了
    sleep(1)
    response = FtxClient.order_history(@sub_account, {market: market_name, orderType: "limit", start_time: time_stamp})
    limit_orders = response["result"]

    while response["hasMoreData"]
      end_time_stamp = response["result"].last["createdAt"].to_time.to_i
      response = FtxClient.order_history(@sub_account, {market: market_name, orderType: "limit", start_time: time_stamp, end_time: end_time_stamp})
      limit_orders += response["result"]
    end

    limit_orders.each {|o| o["status"] = "new"} unless @grid_setting["status"] == "new"

    return limit_orders
  end

  def create_or_update_orders_status!(ftx_orders)
    result = {created: 0, updated: 0}
    return result if ftx_orders.empty?
    
    ftx_order_ids = ftx_orders.pluck("id")
    db_orders = @grid_setting.grid_orders.where(ftx_order_id: ftx_order_ids)
    db_order_ids = db_orders.pluck(:ftx_order_id).map(&:to_i)
    
    new_orders_tbu = []
    existed_orders_tbu = []
    
    ftx_orders.each do |order|
      if db_order_ids.include?(order["id"])
        db_order = db_orders.detect {|db_order| db_order["ftx_order_id"] == order["id"]}
        db_order.attributes = attributes_from_ftx_to_db(order)

        existed_orders_tbu << db_order.attributes
        result[:updated] += 1
      else
        db_order = GridOrder.new(
          "market_name"=> order["market"],
          "grid_setting_id" => @grid_setting.id,
          "ftx_order_id" => order["id"],
          "created_at" => DateTime.now,
          "updated_at" => DateTime.now)
        db_order.attributes = attributes_from_ftx_to_db(order)

        new_orders_tbu << db_order.attributes.except!("id")
        result[:created] += 1
      end
    end

    GridOrder.upsert_all(new_orders_tbu) unless new_orders_tbu.empty?
    GridOrder.upsert_all(existed_orders_tbu) unless existed_orders_tbu.empty?

    return result
  end

  def bias_required_calc(missing_grids)
    market_name = @grid_setting["market_name"]

    size_value, size_step =  @grid_setting["order_size"], @grid_setting["size_step"]
    spot_in_amount = @grid_setting["input_spot_amount"]

    # check bias to operate
    missing_grids_bias = missing_grids["sell"].size - missing_grids["buy"].size

    if @grid_setting["status"] == "new"
      init_required_amount = missing_grids["sell"].size * size_value
      spot_in_bias = init_required_amount - spot_in_amount

        # 需要買的數量
      if spot_in_bias >= 0
        bias_required_amount = spot_in_bias
      else
        # 在新setting中更新實際使用量
        @grid_setting.update(input_spot_amount: init_required_amount)
        bias_required_amount = 0
      end
    else
      bias_required_amount = missing_grids_bias * size_value
      usd_required_amount = missing_grids["buy"].sum * size_value

      unless bias_required_amount == 0
        target_name = market_name.split("/")[0]
        usd_available, spot_available, market_price = 0, 0, 0

        FtxClient.wallet_balances(@sub_account)["result"].each do |balance| 
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

    logger.info(@grid_setting.id) {"missing buy_grids        = #{missing_grids["buy"].size}: #{missing_grids["buy"]}"}
    logger.info(@grid_setting.id) {"missing sell_grids       = #{missing_grids["sell"].size}: #{missing_grids["sell"]}"}
    logger.info(@grid_setting.id) {"missing_grids_bias       = #{missing_grids_bias}"}
    logger.info(@grid_setting.id) {"spot_in_amount           = #{spot_in_amount}"}
    logger.info(@grid_setting.id) {"bias_required_amount     = #{bias_required_amount}"}

    return bias_required_amount
  end

  def bias_required_amount_exec(bias_required_amount)
    market_name = @grid_setting["market_name"]
    size_step = @grid_setting["size_step"]
    market_orders = []

    time_stamp = Time.now.to_i - 2
    order_side = bias_required_amount > 0 ? "buy" : "sell"
    bias_remained_amount = bias_required_amount
    payload_market = {market: market_name, side: order_side, price: nil, type: "market", size: nil}

    last = {executed_amount: 0, batch_amount: 0, bias_remained_amount: 0}

    dead_loop = 0

    until bias_remained_amount == 0
      market_orders = FtxClient.order_history(@sub_account, {market: market_name, orderType: "market", start_time: time_stamp})["result"]

      executed_amount = market_orders.sum {|order| order["filledSize"] if order["status"] == "closed" && order["side"] == order_side}
      executed_amount = 0 - executed_amount if order_side == "sell"

      logger.info(@grid_setting.id) {"executed_amount          = " + executed_amount.to_s}

      bias_remained_amount = ((bias_required_amount - executed_amount) / size_step).round(0) * size_step
      batch_amount = batch_amount_calc(bias_remained_amount)

      unless batch_amount == 0
        logger.info(@grid_setting.id) {"executing amount         = #{batch_amount}/#{bias_remained_amount}"}
        payload = payload_market.merge({size: batch_amount.abs})

        order_result = FtxClient.place_order(@sub_account, payload)["result"]
        logger.info(@grid_setting.id) {"payload                  = " + payload.to_s}
        logger.info(@grid_setting.id) {"result                   = " + order_result_to_output(order_result)}

        dead_loop += last[:executed_amount] == executed_amount && last[:batch_amount] == batch_amount && last[:bias_remained_amount] == bias_remained_amount ? 1 : -dead_loop

        last[:executed_amount] = executed_amount
        last[:batch_amount] = batch_amount
        last[:bias_remained_amount] = bias_remained_amount

        sleep(2)     
      end

      if dead_loop >=3
        logger.error(@grid_setting.id) {"bias_required_amount_exec= dead_loop, quit!"}
        # 回傳已執行
        return market_orders
      end
    end
    # 需filter未執行的
    return market_orders
  end

  def batch_amount_calc(target_amount)
    size_step = @grid_setting["size_step"]

    return 0 if target_amount == 0

    side_name = target_amount > 0 ? "asks" : "bids"

    orderbook = FtxClient.orderbook(@grid_setting["market_name"] ,:depth => 1)["result"]

    batch_size_limit = ((orderbook[side_name][0][1] / 1.618) / size_step).round(0) * size_step
    batch_size_limit = 0 - batch_size_limit if target_amount < 0

    batch_amount = target_amount.abs >= batch_size_limit.abs ? batch_size_limit : target_amount

    return batch_amount
  end

  def del_grid_state(id, type = "")
    redis_key = "sub_account:#{@sub_account.id}:grid_setting:#{id}"
    redis_key += ":#{type}" unless type.empty?
    Redis.new.del(redis_key)
  end

  def get_grid_state(id, type = "")
    redis_key = "sub_account:#{@sub_account.id}:grid_setting:#{id}"
    redis_key += ":#{type}" unless type.empty?
    Redis.new.get(redis_key)
  end

  def set_grid_state(id, data, type = "")
    redis_key = "sub_account:#{@sub_account.id}:grid_setting:#{id}"
    redis_key += ":#{type}" unless type.empty?
    Redis.new.set(redis_key, data)
  end
end

