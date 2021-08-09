class OrderExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(funding_order_id)
    @funding_order = FundingOrder.find(funding_order_id)
    order_status = @funding_order["order_status"]

    return unless order_status == "Underway"
    
    puts "sidekiq OrderExecutorJob for funding_order_id: #{funding_order_id} starting..."

    @coin = Coin.find(@funding_order.coin_id)

    spot_name = @coin.name
    perp_name = "#{@coin.name}-PERP"

    order_config = get_order_config(@coin,@funding_order,spot_name,perp_name)
    order_status = order_config["order_status"] if order_config["order_status"]


    while order_status == "Underway"

      # BTC/USD, BTC-PERP, BTC-0626
      spot_data = FtxClient.market_info("#{spot_name}/USD")
      perp_data = FtxClient.market_info(perp_name)

      order_status = "FtxClient.market_info result Error" unless spot_data["success"] && perp_data["success"]

      case order_config["direction"]
      when "more"
        current_ratio = ((perp_data["result"]["bid"] / spot_data["result"]["ask"] - 1 ) * 100)
      when "less"
        current_ratio = ((spot_data["result"]["bid"] / perp_data["result"]["ask"] - 1 ) * 100)
      end

      puts "#{Time.now.strftime('%H:%M:%S')}: funding_order_id: #{funding_order_id} => #{spot_name}, Current ratio: #{current_ratio}, Threshold: #{@funding_order.threshold}, Direction: #{order_config["direction"]}" if Time.now.to_i % 30 == 0

      if current_ratio > @funding_order.threshold

        spot_order_size = order_sizer("spot",@coin,@funding_order,order_config)
        
        perp_order_size = order_sizer("perp",@coin,@funding_order,order_config)

        payload = {market: nil, side: nil, price: nil, type: "market", size: nil}

        payload_spot = payload.merge({market: "#{spot_name}/USD", size: spot_order_size})
        payload_perp = payload.merge({market: perp_name, size: perp_order_size})

        case order_config["direction"]
        when "more"
          # 先買現貨，再空永續
          payload_spot[:side] = "buy"
          payload_perp[:side] = "sell"
        
          spot_order_result = FtxClient.place_order(payload_spot)
          perp_order_result = FtxClient.place_order(payload_perp)

        when "less"
          # 先平永續，再賣現貨
          payload_perp[:side] = "buy"
          payload_spot[:side] = "sell"

          perp_order_result = FtxClient.place_order(payload_perp)
          spot_order_result = FtxClient.place_order(payload_spot)
        end
        
puts 'payload_spot:' + payload_spot.to_s
puts 'spot_order_result:'
puts spot_order_result.to_json

puts 'payload_perp:' + payload_perp.to_s
puts 'perp_order_result:'
puts perp_order_result.to_json

        order_config = get_order_config(@coin,@funding_order,spot_name,perp_name)
        order_status = order_config["order_status"] if order_config["order_status"]
      end

      if order_status == "Underway"
        FundingOrder.uncached do
          @funding_order = FundingOrder.find(funding_order_id)
          order_status = @funding_order["order_status"]
        end
      end
    end
      
    @funding_order["order_status"] = order_status
    @funding_order.save

    if order_status == "Close"
      puts "sidekiq OrderExecutorJob for funding_order_id: #{funding_order_id} complete."
    else
      puts "sidekiq OrderExecutorJob for funding_order_id: #{funding_order_id} stoped with errors:"
      puts "order_status:" + order_status
    end
  end

def order_sizer(type,coin,funding_order,order_config)
  case type
  when "spot"
    config_type = "spot_steps"
  when "perp"
    config_type = "perp_steps"
  end

  if order_config[config_type].abs >= funding_order.acceleration
    return funding_order.acceleration * coin.sizeIncrement
  else
    return order_config[config_type].abs * coin.sizeIncrement
  end
end

  def get_order_config(coin,funding_order,spot_name,perp_name)
    tmp = {"order_status" => funding_order["order_status"]}

    account_data = get_account_amount(spot_name,perp_name)

    if account_data["error_msg"]
      tmp["order_status"] = account_data["error_msg"] 
      return tmp
    end 

    puts 'account_data:' + account_data.to_json

    tmp["spot_bias"] = funding_order.target_coin_amount - account_data[spot_name]
    tmp["spot_steps"] = (tmp["spot_bias"] / coin.sizeIncrement).round(0)

    tmp["perp_bias"] = funding_order.target_perp_amount - account_data[perp_name]
    tmp["perp_steps"] = (tmp["perp_bias"] / coin.sizeIncrement).round(0)

    tmp["direction"] = tmp["spot_steps"] > tmp["perp_steps"] ? "more" : "less"
    tmp["order_status"] = "Close" if tmp["spot_steps"] == 0 && tmp["perp_steps"] == 0

    print 'spot_bias:' + tmp["spot_bias"].to_s
    puts ' => spot_steps:' + tmp["spot_steps"].to_s
    print 'perp_bias:' + tmp["perp_bias"].to_s
    puts ' => perp_steps:' + tmp["perp_steps"].to_s
    puts 'direction:' + tmp["direction"].to_s
    puts 'order_status:' + tmp["order_status"].to_s

    return tmp
  end

  def get_account_amount(spot_name,perp_name)
    tmp = {}

    tmp[spot_name] = 0
    tmp[perp_name] = 0

    wallet_balances_data = FtxClient.wallet_balances
    positions_data = FtxClient.positions

    tmp["error_msg"] = "FtxClient.wallet_balances result Error" unless wallet_balances_data["success"]
    tmp["error_msg"] = "FtxClient.positions result Error" unless positions_data["success"]
    
    return tmp["error_msg"] if tmp["error_msg"]

    wallet_balances_data["result"].each do |result|
      tmp[spot_name] = result["total"] if result["coin"] == spot_name
    end

    positions_data["result"].each do |result|
      tmp[perp_name] = result["netSize"] if result["future"] == perp_name
    end

    return tmp
  end
end
