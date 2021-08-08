class OrderExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(funding_order_id)
    @funding_order = FundingOrder.find(funding_order_id)
    order_status = @funding_order["order_status"]

    return unless order_status == "Underway"
    
    @coin = Coin.find(@funding_order.coin_id)

    spot_name = @coin.name
    perp_name = "#{@coin.name}-PERP"

    account_data = get_account_amount(spot_name,perp_name)

puts 'account_data: #{account_data}'

    if account_data["error_msg"]
      order_status = account_data["error_msg"]
    else
      spot_bias = @funding_order.target_coin_amount - account_data[spot_name]
      spot_steps = (spot_bias / @coin.sizeIncrement).round(0)

puts 'spot_bias: #{spot_bias}'
puts 'spot_steps: #{spot_steps}'

      perp_bias = @funding_order.target_perp_amount - account_data[perp_name]
      perp_steps = (perp_bias / @coin.sizeIncrement).round(0)

puts 'perp_bias: #{perp_bias}'
puts 'perp_steps: #{perp_steps}'

      direction = spot_steps > perp_steps ? "more" : "less"
      order_status = "Close" if spot_steps == 0 && perp_steps == 0

puts 'direction: #{direction}'
puts 'order_status: #{order_status}'

    end

    puts "sidekiq OrderExecutorJob for funding_order_id: #{funding_order_id} starting..."

    while order_status == "Underway"

      # BTC/USD, BTC-PERP, BTC-0626
      spot_data = FtxClient.market_info("#{spot_name}/USD")
      perp_data = FtxClient.market_info(perp_name)

      order_status = "FtxClient.market_info result Error" unless spot_data["success"] && perp_data["success"]

      case direction
      when "more"
        current_ratio = ((perp_data["result"]["bid"] / spot_data["result"]["ask"] - 1 ) * 100)

puts 'perp_data["result"]["bid"]: #{perp_data["result"]["bid"]}'
puts 'spot_data["result"]["ask"]: #{spot_data["result"]["ask"]}'

      when "less"
        current_ratio = ((spot_data["result"]["bid"] / perp_data["result"]["ask"] - 1 ) * 100)

puts 'spot_data["result"]["bid"]: #{spot_data["result"]["bid"]}'
puts 'perp_data["result"]["ask"]: #{perp_data["result"]["ask"]}'

      end

      puts "#{Time.now.strftime('%H:%M:%S')}: funding_order_id: #{funding_order_id}, #{spot_name}: Current ratio: #{current_ratio}" if Time.now.to_i % 20 == 0

      if current_ratio > @funding_order.threshold

        spot_size = spot_steps.abs >= @funding_order.acceleration ? @funding_order.acceleration : spot_steps.abs
        perp_size = perp_steps.abs >= @funding_order.acceleration ? @funding_order.acceleration : perp_steps.abs

        payload = {market: nil, side: nil, price: nil, type: "market", size: nil}

        payload_spot = payload.merge({market: "#{spot_name}/USD", size: spot_size})
        payload_perp = payload.merge({market: perp_name, size: perp_size})

        case direction
        when "more"
          # 先買現貨，再空永續
          payload_spot[:side] = "buy"
          payload_perp[:side] = "sell"
        
puts 'payload_spot: #{payload_spot}'
puts 'payload_perp: #{payload_perp}'
        
# FtxClient.place_order(payload_spot)
# FtxClient.place_order(payload_perp)

        when "less"
          # 先平永續，再賣現貨
          payload_perp[:side] = "buy"
          payload_spot[:side] = "sell"
        
puts 'payload_spot: #{payload_spot}'
puts 'payload_perp: #{payload_perp}'

# FtxClient.place_order(payload_perp)
# FtxClient.place_order(payload_spot)

        end
        


        account_data = get_account_amount(spot_name,perp_name)

puts 'account_data: #{account_data}'

        if account_data["error_msg"]
          order_status = account_data["error_msg"]
        else
          spot_bias = @funding_order.target_coin_amount - account_data[spot_name]
          spot_steps = (spot_bias / @coin.sizeIncrement).round(0)

puts 'spot_bias: #{spot_bias}'
puts 'spot_steps: #{spot_steps}'

          perp_bias = @funding_order.target_perp_amount - account_data[perp_name]
          perp_steps = (perp_bias / @coin.sizeIncrement).round(0)

puts 'perp_bias: #{perp_bias}'
puts 'perp_steps: #{perp_steps}'

          direction = spot_steps > perp_steps ? "more" : "less"
          order_status = "Close" if spot_steps == 0 && perp_steps == 0

puts 'direction: #{direction}'
puts 'order_status: #{order_status}'

        end



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
      puts "sidekiq OrderExecutorJob for funding_order_id: #{funding_order_id} abort with errors:"
      puts order_status
    end
  end

  def get_account_amount(spot_name,perp_name)

    tmp[spot_name] = 0
    tmp[perp_name] = 0

    wallet_balances_data = FtxClient.wallet_balances
    positions_data = FtxClient.positions

    tmp["error_msg"] = "FtxClient.wallet_balances result Error" unless wallet_balances_data["success"]
    tmp["error_msg"] = "FtxClient.positions result Error" unless positions_data["success"]
    
    return order_status if order_status

    wallet_balances_data["result"].each do |result|
      tmp[spot_name] = result["availableWithoutBorrow"] if result["coin"] == spot_name
    end

    positions_data["result"].each do |result|
      tmp[perp_name] = result["netSize"] if result["future"] == perp_name
    end

    return tmp
  end
end
