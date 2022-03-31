class WebhookController < ApplicationController
  protect_from_forgery except: :receiver

  def receiver
    permitted = tv_params_permit
    sub_account = permitted["strategy_name"]
    market = permitted["order_market"].split("USDT")[0] + "-PERP"
    side = permitted["order_action"]
    size = permitted["order_size"]

    payload = {market: market, side: side, price: nil, type: "market", size: size}
    
    puts payload
    order_result = FtxClient.place_order(sub_account, payload) unless size == 0
    puts order_result

    render plain: 'ok', status: 200
  end

private
  def tv_params_permit
    params.permit(:strategy_name, :order_action, :order_size, :order_price, :order_market, :strategy_position_size )
  end
end
