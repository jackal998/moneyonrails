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
    @coin = params["coin"] ? Coin.find(params["coin"]) : Coin.find_by("name = ?", "BTC")

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
      :coin => @coin, 
      :coin_name => @coin.name,
      :original_coin_amount => balances[@coin.name]["amount"],
      :original_perp_amount => @position["netSize"]
      )

    render locals: {balances: balances}
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
end