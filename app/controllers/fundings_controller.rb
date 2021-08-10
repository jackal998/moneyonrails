class FundingsController < ApplicationController
  require 'ftx_client'
  def index
    helpers.update_market_infos if Time.now - CurrentFundStat.last.updated_at > 15
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
    @ftx_account = FtxClient.account

    balances = ftx_wallet_balance
    render locals: {balances: balances}
  end

  def show
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")

    @coin = params["coin"] ? Coin.find(params["coin"]) : Coin.find_by("name = ?", "BTC")

    @funding_orders = FundingOrder.includes(:coin).all
    @underway_order = @funding_orders.where(:order_status => "Underway").last
    
    @position = {"netSize" => 0, "cost" => 0}
    FtxClient.account["result"]["positions"].each do |position|
      if position["future"].split("-")[0] == @coin.name
        @position = {
          "netSize" => position["netSize"],
          "cost" => position["cost"]}
      end
    end

    @fund_stat = @coin.current_fund_stat
    rates = @coin.rates.where("time > ?", Time.now - 6.weeks).order("time asc")

    @line_chart_data = rates.map { |r| [r.time.strftime('%m/%d %H:%M'),r.rate*100]}
    @zeros = @line_chart_data.map { |t,r| [t,0] }

    balances = ftx_wallet_balance
    balances[@coin.name] = {"amount"=>0.0, "usdValue"=>0.0} unless balances[@coin.name]

    @funding_order = FundingOrder.new(
      :coin_id => @coin.id, 
      :coin_name => @coin.name,
      :original_coin_amount => balances[@coin.name]["amount"],
      :original_perp_amount => @position["netSize"]
      )

    render locals: {balances: balances}
  end

  def createorder
    @funding_order = FundingOrder.new(createorder_params)

    if @funding_order.target_perp_amount && @funding_order.target_perp_amount != @funding_order.original_perp_amount
      @funding_order["order_status"] = "Underway"

      @funding_order.save
      OrderExecutorJob.perform_later(@funding_order.id)

      redirect_to funding_show_path(coin: @funding_order.coin_id)
    end
  end

  def abortorder
    @funding_order = FundingOrder.find(params["funding_order"]["id"])
    @funding_order.update(:order_status => "Abort")

    redirect_to funding_show_path(coin: @funding_order.coin_id)
  end

private
  def ftx_wallet_balance
    balances = {"totalusdValue" => 0.00}

    ftx_wallet_balances_response = FtxClient.wallet_balances
    if ftx_wallet_balances_response["success"] 
      ftx_wallet_balances_response["result"].each do |result|
        balances[result["coin"]] = {"amount" => result["availableWithoutBorrow"], "usdValue" => result["usdValue"]}
        balances["totalusdValue"] += result["usdValue"]
      end
    end    
    return balances
  end

  def createorder_params
    params.require(:funding_order).permit(:coin_id,:coin_name,
                                          :original_coin_amount,:original_perp_amount,
                                          :target_coin_amount,:target_perp_amount,
                                          :acceleration,:threshold)
  end
end