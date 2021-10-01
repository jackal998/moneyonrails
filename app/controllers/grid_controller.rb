class GridController < ApplicationController
  require 'ftx_client'

  def index
    market_name = index_params["market_name"] ? index_params["market_name"] : "#{index_params["coin_name"]}/USD"

    @market = FtxClient.market_info(market_name)["result"]
    coin_name = @market["type"] == "spot" ? @market["baseCurrency"] : nil

    @grid_setting = GridSetting.new(market_name: market_name, price_step: @market["priceIncrement"], size_step: @market["sizeIncrement"])
    @grid_settings = GridSetting.includes(:grid_orders).where(status: ["active", "closing"])

    balances = ftx_wallet_balance
    ["USD", coin_name].each { |c| balances[c] = {"amount"=>0.0, "usdValue"=>0.0} unless balances[c] }

    render locals: {balances: balances, coin_name: coin_name, tv_market_name: tv_market_name(market_name)}
  end

  def creategrid
    @grid_setting = GridSetting.find(1)
    # @grid_setting = GridSetting.new(creategrid_params)

    @grid_setting["status"] = "active"

    puts @grid_setting.attributes
    @grid_setting.save
    # GridExecutorJob.perform_later(@grid_setting[:id])
aaaa
    redirect_to grid_path(:market_name => @grid_setting[:market_name])
  end

  def closegrid
    @grid_setting = GridSetting.find(params["grid_setting"]["id"])
    @grid_setting.update(:status => "closing") if @grid_setting.status == "active"
    # valid_message = "close" if order_data["price"] == close_price && order_data["size"] == grid_setting["order_size"]
aaaa
    redirect_to grid_path(:market_name => @grid_setting[:market_name])
  end

private
  def tv_market_name(ftx_market_name)
    ftx_market_name.dup.sub!('-', '') || ftx_market_name.dup.sub!('/', '')
  end

  def ftx_wallet_balance
    balances = {"totalusdValue" => 0.00}

    ftx_wallet_balances_response = FtxClient.wallet_balances("GridOnRails")
    if ftx_wallet_balances_response["success"] 
      ftx_wallet_balances_response["result"].each do |result|
        balances[result["coin"]] = {"amount" => result["availableWithoutBorrow"], "usdValue" => result["usdValue"]}
        balances["totalusdValue"] += result["usdValue"]
      end
    end    

    balances["USD"] = balances.delete("USD") if balances["USD"]
    return balances
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
