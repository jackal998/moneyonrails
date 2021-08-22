class GridExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(grid_setting_id)
    @grid_setting = GridSetting.find(grid_setting_id)
    coin_name = @grid_setting["coin_name"]

    return unless @grid_setting["status"] == "active"
    
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
    error_msg += "input_USD_amount(#{@grid_setting["input_USD_amount"]}) invalid. " unless input_USD_check(@grid_setting, market_on_grid_value, buy_grids, sell_grids)

    init_balances = ftx_wallet_balance
    error_msg += "wallet_balances(GridOnRails) result unsuccess. " if init_balances.empty?
    return error_msg unless error_msg.empty?
    # @grid_setting params check ok

    # check how many target to buy (sell_grids)
    to_buy_amount = size_step
    to_buy_total_amount = sell_grids * size_step

    payload_market = {market: "#{coin_name}/USD", side: nil, price: nil, type: "market", size: nil}
    payload_limit = {market: "#{coin_name}/USD", side: nil, price: nil, type: "limit", size: size_value}

    while to_buy_amount > 0
      # @grid_setting["input_spot_amount"]
      curr_balances = ftx_wallet_balance
      error_msg += "wallet_balances(GridOnRails) result unsuccess. " if curr_balances.empty?
      return error_msg unless error_msg.empty?

      to_buy_amount = to_buy_amount_calc(coin_name, to_buy_total_amount, curr_balances, init_balances, size_step)
      break unless to_buy_amount > 0
        
      payload_market_buy = payload_market.merge({side: "buy", size: to_buy_amount})

      order_result = FtxClient.place_order("GridOnRails", payload_market_buy)

      bought_order_ids = []
      bought_order_ids << save_order_result!(@grid_setting, order_result) if order_result["success"]

      puts 'payload_spot:' + payload_market_buy.to_s
      puts 'spot_order_result:'
      puts order_result.to_json

      sleep(1)
    end

    # update market buy order status from ftx
    update_order_status!(coin_name, bought_order_ids)

    # native check if grids value is integer
    (1..sell_grids).each do |i|
      order_price = market_on_grid_value + gap_value * i

      payload_limit_sell = payload_limit.merge({side: "sell", price: order_price})

      order_result = FtxClient.place_order("GridOnRails", payload_limit_sell)
      
      save_order_result!(@grid_setting, order_result) if order_result["success"]

      puts 'payload_limit_sell:' + payload_limit_sell.to_s
      puts 'payload_limit_sell_result:'
      puts order_result.to_json
    end

    (1..buy_grids).each do |i|
      order_price = market_on_grid_value - gap_value * i

      payload_limit_buy = payload_limit.merge({side: "buy", price: order_price})

      order_result = FtxClient.place_order("GridOnRails", payload_limit_buy)

      save_order_result!(@grid_setting, order_result) if order_result["success"]

      puts 'payload_limit_buy:' + payload_limit_buy.to_s
      puts 'payload_limit_buy_result:'
      puts order_result.to_json
    end
    # buy spots and grids init ok
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
      return (upper_value - lower_value) / gap_value if market_on_grid_value >= upper_value
      return (market_on_grid_value - lower_value) / gap_value if market_on_grid_value > lower_value
      return 0
    when "sell"
      return (upper_value - lower_value) / gap_value + 1 if market_on_grid_value < lower_value
      return (upper_value - market_on_grid_value) / gap_value if market_on_grid_value < upper_value
      return 0
    end
  end

  def input_USD_check(grid_setting, market_on_grid_value, buy_grids, sell_grids)
    lower_value = grid_setting["lower_limit"]
    gap_value = grid_setting["grid_gap"]
    size_value = grid_setting["order_size"]

    buy_grids_USD_required = (buy_grids * (buy_grids - 1) / 2) * grid_setting["grid_gap"] + buy_grids * grid_setting["lower_limit"]
    sell_grids_USD_required = sell_grids * market_on_grid_value

    return grid_setting["input_USD_amount"] == ((sell_grids_USD_required + buy_grids_USD_required) * grid_setting["order_size"]).round(2)
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

  def update_order_status!(coin_name, order_ids)
    orders = GridOrder.where("ftx_order_id = ?", order_ids)

    orders_result = {}
    ftx_order_history_response = FtxClient.order_history("GridOnRails", market: "#{coin_name}/USD")

    ftx_order_history_response["result"].each do |result|
      if order_ids.include?(result["id"])
        order = orders.detect {|order| order["ftx_order_id"] == result["id"]}

        order.update(
           "market"=> result["market"],
           "order_type"=> result["type"],
           "side"=> result["side"],
           "price"=> result["price"],
           "size"=> result["size"],
           "status"=> result["status"],
           "filledSize"=> result["filledSize"],
           "remainingSize"=> result["remainingSize"],
           "avgFillPrice"=> result["avgFillPrice"],
           "createdAt"=> result["createdAt"])
      end
    end
    
  end
end
