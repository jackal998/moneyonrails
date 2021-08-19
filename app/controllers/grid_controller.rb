class GridController < ApplicationController
  require 'ftx_client'

  def index
    coin_name = params["coin_name"] ? params["coin_name"] : "BTC"
    @coin = Coin.find_by("name = ?", coin_name)
    
    @grid_setting = GridSetting.new(:coin_id => @coin.id, :coin_name => @coin.name)
    balances = ftx_wallet_balance

    render locals: {balances: balances}
  end

  def creategrid
    @grid_setting = GridSetting.new(creategrid_params)

    @grid_setting["status"] = "active"
    # @grid_setting.save
    # OrderExecutorJob.perform_later(@funding_order.id)
    GridExecutorJob.perform_later(@grid_setting[:coin_name])

    redirect_to grid_path(:coin_name => @grid_setting[:coin_name])
  end

private
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
    params.require(:grid_setting).permit(:coin_id,:coin_name,
                                          :lower_limit,:upper_limit,:girds,:grid_gap,
                                          :input_USD_amount,:input_spot_amount,
                                          :trigger_price,:threshold,
                                          :stop_loss_price,:take_profit_price)
  end
end
