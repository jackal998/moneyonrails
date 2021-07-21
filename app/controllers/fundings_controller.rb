class FundingsController < ApplicationController
  def index
    @coins = Coin.all
    
  end
end
