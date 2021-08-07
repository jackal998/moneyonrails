class OrderExecutorJob < ApplicationJob
  queue_as :default
  require "ftx_client"

  def perform(funding_order_id)
    @funding_order = FundingOrder.find(funding_order_id)
    order_status = @funding_order["order_status"]

    return unless order_status == "Underway"
    
    @coin = Coin.find(@funding_order.coin_id)
    coin_name = @coin.name
    perp_name = "#{@coin.name}-PERP"

    order_status = compare_account_with_order(coin_name, perp_name, @funding_order)

    puts "sidekiq OrderExecutorJob for funding_order_id: #{funding_order_id} starting..."

    while order_status == "Underway"

      # BTC/USD, BTC-PERP, BTC-0626
      spot_data = FtxClient.market_info("#{coin_name}/USD")
      perp_data = FtxClient.market_info(perp_name)

      order_status = "FtxClient.market_info result Error" unless spot_data["success"] && perp_data["success"]

      current_ratio = ((perp_data["result"]["bid"] / spot_data["result"]["ask"] - 1 ) * 100)
      puts "#{Time.now.strftime('%H:%M:%S')}: funding_order_id: #{funding_order_id}, #{coin_name}: Current ratio: #{current_ratio}" if Time.now.to_i % 20 == 0

      if current_ratio > @funding_order.threshold

        payloadforspot = {
          "market" => "#{coin_name}/USD",
          "side" => "buy",
          "type" => "market",
          "size" => @coin.sizeIncrement
        }
        
        FtxClient.place_order(payloadforspot)



        puts "acceleration: 3"


        order_status = compare_account_with_order(coin_name, perp_name, @funding_order)
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
      puts order_status
    end
  end

  def compare_account_with_order(coin_name,perp_name,funding_order)
    order_status = funding_order["order_status"]

    coin_amount = 0
    perp_amount = 0

    wallet_balances_data = FtxClient.wallet_balances
    positions_data = FtxClient.positions

    order_status = "FtxClient.wallet_balances result Error" unless wallet_balances_data["success"]
    order_status = "FtxClient.positions result Error" unless positions_data["success"]
    
    if order_status == "Underway"
      wallet_balances_data["result"].each do |result|
        coin_amount = result["availableWithoutBorrow"] if result["coin"] == @coin.name
      end

      positions_data["result"].each do |result|
        perp_amount = result["netSize"] if result["future"] == perp_name
      end

      order_status = "Close" if @funding_order.target_perp_amount == perp_amount && ((coin_amount - @funding_order.target_coin_amount).abs / coin_amount) < 0.01
    end

    return order_status
  end
end
