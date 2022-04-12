class WebhookController < ApplicationController
  protect_from_forgery except: :receiver

  def receiver
    permitted = tv_params_permit

    market_permited = permitted["order_market"].split(/(?=(USD)|(USDT)|(PERP)|(-PERP))/)
    render plain: "sufix mismatch: #{permitted['order_market']}", status: 200 if market_permited.size == 1
      
    market = market_permited[0] + "-PERP"
    market_info = FtxClient.market_info(market)["result"]

    sub_account = permitted["strategy_name"]
    side = permitted["order_action"]
    size = permitted["order_size"]

    if market_info
      price = side == "buy" ? market_info["bid"] : market_info["ask"]
    else
      price = permitted["order_price"]
    end

    payload = {market: market, side: side, price: price, type: "limit", size: size}

    puts payload

    order_result = {}
    retrys = 0
    until order_result["success"]
      order_result = FtxClient.place_order(sub_account, payload)
      puts order_result
      puts "Retry: #{retrys}" if retrys > 0
      retrys += 1

      sleep(5) unless order_result["success"]
    end

    render plain: 'ok', status: 200
  end

private
  def tv_params_permit
    params.permit(:strategy_name, :order_action, :order_size, :order_price, :order_market, :strategy_position_size )
  end
end
