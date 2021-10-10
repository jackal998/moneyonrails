class GridController < ApplicationController
  require 'ftx_client'

  def index
    market_name = index_params["market_name"] ? index_params["market_name"] : "#{index_params["coin_name"]}/USD"

    @market = FtxClient.market_info(market_name)["result"]
    coin_name = @market["type"] == "spot" ? @market["baseCurrency"] : nil

    @grid_setting = GridSetting.new(market_name: market_name, price_step: @market["priceIncrement"], size_step: @market["sizeIncrement"])
    @grid_settings = GridSetting.includes(:grid_orders).where(status: ["active", "closing"])

    balances = ftx_wallet_balance("GridOnRails", coin_name)

    render locals: {balances: balances, coin_name: coin_name, tv_market_name: tv_market_name(market_name)}
  end

  def creategrid
    @grid_setting = GridSetting.new(creategrid_params)
    @grid_setting["status"] = "active"
    puts @grid_setting.attributes
    @grid_setting.save

    GridExecutorJob.perform_later(@grid_setting[:id])
    redirect_to grid_path(:market_name => @grid_setting[:market_name])
  end

  def closegrid
    @grid_setting = GridSetting.find(params["grid_setting"]["id"])
    @grid_setting.update(:status => "closing") if @grid_setting.status == "active"

    close_price = @grid_setting["upper_limit"] + @grid_setting["lower_limit"] - @grid_setting["grid_gap"]
    payload = {market: @grid_setting[:market_name], side: "sell", price: close_price, type: "limit", size: @grid_setting["order_size"]}

    order_result = FtxClient.place_order("GridOnRails", payload)["result"]
    puts "FtxClient order result:" + order_result["result"].select {|k,v| {k => v} if ["market","side","price","size","status","createdAt"].include?(k)}.to_s

    redirect_to grid_path(:market_name => @grid_setting[:market_name])
  end

private
  def tv_market_name(ftx_market_name)
    ftx_market_name.dup.sub!('-', '') || ftx_market_name.dup.sub!('/', '')
  end

  def creategrid_params
    params.require(:grid_setting).permit(:market_name, :order_size, :price_step, :size_step,
                                          :lower_limit,:upper_limit,:grids,:grid_gap,
                                          :input_USD_amount,:input_spot_amount,
                                          :trigger_price,:threshold,
                                          :stop_loss_price,:take_profit_price)
  end

  def index_params
    params.permit(:coin_name, :market_name)
  end
end
