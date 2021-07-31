class FundingsController < ApplicationController
  require 'ftx_client'
  def index
    balances = {"totalusdValue" => 0.00}

    helpers.update_market_infos if Time.now - CurrentFundStat.last.updated_at > 15
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
    
    @ftx_account = FtxClient.account

    @ftx_wallet_balances = FtxClient.wallet_balances
    if @ftx_wallet_balances["success"] 
      @ftx_wallet_balances["result"].each do |result|
        balances[result["coin"]] = result["usdValue"]
        balances["totalusdValue"] += result["usdValue"]
      end
    end
    render locals: {balances: balances}
  end
end