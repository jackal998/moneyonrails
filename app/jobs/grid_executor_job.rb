class GridExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(grid_setting_id)
    @grid_setting = GridSetting.find(grid_setting_id)
    coin_name = @grid_setting["coin_name"]
    setting_status = @grid_setting["status"]

    return unless setting_status == "active"
    
    puts "sidekiq GridExecutorJob for grid_setting_id: #{grid_setting_id} starting..."
    error_msg = ""

    @market = FtxClient.market_info("#{coin_name}/USD")["result"]

    price_step = @market["priceIncrement"]
    size_step = @market["sizeIncrement"]
    market_value = @market["price"]

    upper_value = @grid_setting["upper_limit"]
    lower_value = @grid_setting["lower_limit"]

    grids_value = @grid_setting["grids"]
    gap_value = @grid_setting["grid_gap"]
    size_value = @grid_setting["order_size"]

    error_msg += "grids_value(#{grids_value}) invalid. " if grids_value > ((upper_value - lower_value)/price_step + 1)
    error_msg += "gap_value(#{gap_value}) invalid. " unless gap_value == (((upper_value - lower_value)/price_step)/(grids_value - 1)).round(0) * price_step
    error_msg += "upper_value(#{upper_value}) invalid. " unless upper_value == lower_value + ((grids_value - 1) * gap_value)
    return error_msg unless error_msg.empty?

    market_on_grid_value = ((market_value - lower_value) / gap_value).round(0) * gap_value + lower_value

    buy_grids = grids_calc("buy", market_on_grid_value, upper_value, lower_value, gap_value)
    sell_grids = grids_calc("sell", market_on_grid_value, upper_value, lower_value, gap_value)

    # for restart handling
    init_open_orders = @grid_setting.grid_orders.where(status: ["new", "open"])
    updated_ids = update_order_status!(coin_name, orders: init_open_orders)

puts "setting upper_limit      = #{upper_value}"
puts "setting lower_value      = #{lower_value}"
puts "setting grids_value      = #{grids_value}"
puts "setting gap_value        = #{gap_value}"
puts "setting size_value       = #{size_value}"
puts "setting total buy_grids  = #{buy_grids}"
puts "setting total sell_grids = #{sell_grids}"
    # init_open_orders was changed by .detect & .save in update_order_status!
    spot_bought = 0
    init_open_orders.each do |order|
      if updated_ids.include?(order.id) && order.status == "closed"
        spot_bought += order.filledSize if order.side == "buy" 
        next
      end
      sell_grids -= 1 if order.side == "sell" && sell_grids > 0
      buy_grids -= 1 if order.side == "buy" && buy_grids > 0
    end

    error_msg += "input_USD_amount(#{@grid_setting["input_USD_amount"]}) invalid. " unless input_USD_check(@grid_setting, market_on_grid_value, buy_grids, sell_grids)

    init_balances = ftx_wallet_balance
    error_msg += "wallet_balances(GridOnRails) result unsuccess. " if init_balances.empty?
    return error_msg unless error_msg.empty?
    # @grid_setting params check ok
    # check how many target to buy (sell_grids)
    # 要考慮closed buy已買的數量
    to_buy_total_amount = sell_grids * size_step - spot_bought
    to_buy_amount = to_buy_amount_calc(coin_name, to_buy_total_amount, init_balances, init_balances, size_step)

puts "missing buy_grids        = #{buy_grids}"
puts "missing sell_grids       = #{sell_grids}"
puts "spot_bought              = #{spot_bought}"
puts "to_buy_total_amount      = #{to_buy_total_amount}"

    payload_market = {market: "#{coin_name}/USD", side: nil, price: nil, type: "market", size: nil}
    payload_limit = {market: "#{coin_name}/USD", side: nil, price: nil, type: "limit", size: size_value}

    # loop for batch buy
    bought_order_ids = []

    while to_buy_amount > 0
      payload_market_buy = payload_market.merge({side: "buy", size: to_buy_amount})

      order_result = FtxClient.place_order("GridOnRails", payload_market_buy)

      bought_order_ids << save_order_result!(@grid_setting, order_result) if order_result["success"]

      puts 'payload_spot:' + payload_market_buy.to_s
      puts 'spot_order_result:'
      puts order_result.to_json

      sleep(1)
      # @grid_setting["input_spot_amount"]
      curr_balances = ftx_wallet_balance
      error_msg += "wallet_balances(GridOnRails) result unsuccess. " if curr_balances.empty?
      return error_msg unless error_msg.empty?

      to_buy_amount = to_buy_amount_calc(coin_name, to_buy_total_amount, curr_balances, init_balances, size_step)
    end

    # update market buy order status from ftx
    update_order_status!(coin_name, order_ids: bought_order_ids) unless bought_order_ids.empty?

    open_orders = @grid_setting.grid_orders.where(status: ["new", "open"])

    ref_price = ref_calc(market_on_grid_value, upper_value, lower_value)
    # buy spots and grids init ok

    while setting_status == "active"
      puts "#{Time.now.strftime('%H:%M:%S')}: ref_price: #{ref_price} / sell_grids: #{sell_grids} / buy_grids: #{buy_grids}"

      (1..sell_grids).each do |i|
        order_price = ref_price + gap_value * i
        
        break if open_orders.detect {|order| order["price"] == order_price}

        payload_limit_sell = payload_limit.merge({side: "sell", price: order_price})

        order_result = FtxClient.place_order("GridOnRails", payload_limit_sell)
        
        save_order_result!(@grid_setting, order_result) if order_result["success"]

        puts 'payload_limit_sell:' + payload_limit_sell.to_s
        puts 'payload_limit_sell_result:'
        puts order_result.to_json
      end

      (1..buy_grids).each do |i|
        order_price = ref_price - gap_value * i

        break if open_orders.detect {|order| order["price"] == order_price}

        payload_limit_buy = payload_limit.merge({side: "buy", price: order_price})

        order_result = FtxClient.place_order("GridOnRails", payload_limit_buy)

        save_order_result!(@grid_setting, order_result) if order_result["success"]

        puts 'payload_limit_buy:' + payload_limit_buy.to_s
        puts 'payload_limit_buy_result:'
        puts order_result.to_json
      end

      GridSetting.uncached do
        open_orders = @grid_setting.grid_orders.where(status: ["new", "open"])
      end

      updated_ids = []
      # main grid check update loop
      while updated_ids.empty?
        # grids check ever 3 second
        sleep(3)
        puts "#{Time.now.strftime('%H:%M:%S')}: grid_setting_id: #{grid_setting_id} status: active." if Time.now.to_i % 60 == 0
        updated_ids = update_order_status!(coin_name, orders: open_orders)

        # set to every 15s
        GridSetting.uncached do
          setting_status = GridSetting.find(grid_setting_id).status
        end

        unless setting_status == "active"
          to_cancel_order_ids = @grid_setting.grid_orders.where(status: ["new", "open"]).pluck(:ftx_order_id).map(&:to_i)

          to_cancel_order_ids.each do |order_id|
            cancel_result = FtxClient.cancel_order("GridOnRails", order_id.to_i)
            # puts cancel_result.to_json
          end

          updated_ids = update_order_status!(coin_name, order_ids: to_cancel_order_ids)
        end
      end
      break unless setting_status == "active"

      @market = FtxClient.market_info("#{coin_name}/USD")["result"]
      market_value = @market["price"]
      market_on_grid_value = ((market_value - lower_value) / gap_value).round(0) * gap_value + lower_value
      ref_price = ref_calc(market_on_grid_value, upper_value, lower_value)

      buy_grids = grids_calc("buy", ref_price, upper_value, lower_value, gap_value)
      sell_grids = grids_calc("sell", ref_price, upper_value, lower_value, gap_value)
    end

    puts "Grids were cleaned, See You!"
  end

  def ftx_wallet_balance
    balance = {}
    ftx_wallet_balances_response = FtxClient.wallet_balances("GridOnRails")

    if ftx_wallet_balances_response["success"] 
      ftx_wallet_balances_response["result"].each do |result|
        balance[result["coin"]] = {"amount" => result["availableWithoutBorrow"], "usdValue" => result["usdValue"]}
      end
    end
    return balance
  end

  def grids_calc(side, market_on_grid_value, upper_value, lower_value, gap_value)
    case side
    when "buy"
      return ((upper_value - lower_value) / gap_value).round(0) if market_on_grid_value >= upper_value
      return ((market_on_grid_value - lower_value) / gap_value).round(0) if market_on_grid_value > lower_value
      return 0
    when "sell"
      return ((upper_value - lower_value) / gap_value).round(0) if market_on_grid_value <= lower_value
      return ((upper_value - market_on_grid_value) / gap_value).round(0) if market_on_grid_value < upper_value
      return 0
    end
  end

  def input_USD_check(grid_setting, market_on_grid_value, buy_grids, sell_grids)
    lower_value = grid_setting["lower_limit"]
    gap_value = grid_setting["grid_gap"]
    size_value = grid_setting["order_size"]

    buy_grids_USD_required = (buy_grids * (buy_grids - 1) / 2) * grid_setting["grid_gap"] + buy_grids * grid_setting["lower_limit"]
    sell_grids_USD_required = sell_grids * market_on_grid_value

    return grid_setting["input_USD_amount"] >= ((sell_grids_USD_required + buy_grids_USD_required) * grid_setting["order_size"]).round(2)
  end

  def ref_calc(market_on_grid_value, upper_value, lower_value)
    return upper_value if market_on_grid_value >= upper_value
    return lower_value if market_on_grid_value <= lower_value
    return market_on_grid_value
  end

  def to_buy_amount_calc(coin_name, to_buy_total_amount, curr_balances, init_balances, size_step)
  
    orderbook = FtxClient.orderbook("#{coin_name}/USD" ,:depth => 2)["result"]
    batch_buy_size_limit = ((orderbook["asks"][0][1] / 1.618) / size_step).round(0) * size_step

    to_buy_amount = ((to_buy_total_amount - (curr_balances[coin_name]["amount"] - init_balances[coin_name]["amount"])) / size_step).round(0) * size_step
    to_buy_amount = to_buy_amount >= batch_buy_size_limit ? batch_buy_size_limit : to_buy_amount

    return to_buy_amount
  end

  def save_order_result!(grid_setting, order_result)
    GridOrder.create(
      "coin_id" => grid_setting["coin_id"],
      "coin_name" => grid_setting["coin_name"],
      "grid_setting_id" => grid_setting["id"],
      "ftx_order_id" => order_result["result"]["id"],
      "market" => "#{grid_setting["coin_name"]}/USD",
      "order_type" => order_result["result"]["type"],
      "side" => order_result["result"]["side"],
      "price" => order_result["result"]["price"],
      "size" => order_result["result"]["size"],
      "status" => order_result["result"]["status"],
      "filledSize" => order_result["result"]["filledSize"],
      "remainingSize" => order_result["result"]["remainingSize"],
      "avgFillPrice" => order_result["result"]["avgFillPrice"],
      "createdAt" => order_result["result"]["createdAt"]
      )
    return order_result["result"]["id"]
  end

  def update_order_status!(coin_name, order_ids: nil , orders: nil)
    updated = []

    orders = GridOrder.where(ftx_order_id: order_ids) unless orders
    return updated if orders.empty?
    order_ids = orders.pluck(:ftx_order_id).map(&:to_i)

    ftx_order_history_response = FtxClient.order_history("GridOnRails", market: "#{coin_name}/USD")

    ftx_order_history_response["result"].each do |result|
      if order_ids.include?(result["id"])
        order = orders.detect {|order| order["ftx_order_id"] == result["id"]}

        order.attributes = {
           "market"=> result["market"],
           "order_type"=> result["type"],
           "side"=> result["side"],
           "price"=> result["price"],
           "size"=> result["size"],
           "status"=> result["status"],
           "filledSize"=> result["filledSize"],
           "remainingSize"=> result["remainingSize"],
           "avgFillPrice"=> result["avgFillPrice"],
           "createdAt"=> result["createdAt"]}

        if order.changed?
          order.save
          updated << result["id"]
        end
      end
    end
    return updated
  end
end
