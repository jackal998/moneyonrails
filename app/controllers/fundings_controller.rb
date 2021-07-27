class FundingsController < ApplicationController
  def index

    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
  end

  
end
