class CreateCurrentFundStats < ActiveRecord::Migration[6.1]
  def change
    create_table :current_fund_stats do |t|
      t.integer :coin_id, :index => true

      # data from api https://ftx.com/api/futures/{BTC-PERP}/stats
      t.decimal :nextFundingRate
      t.datetime :nextFundingTime
      t.decimal :openInterest

      # data from api https://ftx.com/api/markets
      t.string :market_type
      t.decimal :spot_price_usd
      t.decimal :spot_bid_usd
      t.decimal :spot_ask_usd
      t.decimal :spot_volume

      t.decimal :perp_price_usd
      t.decimal :perp_bid_usd
      t.decimal :perp_ask_usd
      t.decimal :perp_volume

      # data from calc
      t.decimal :success_rate_past_48_hrs
      t.decimal :success_rate_past_week
      t.decimal :irr_past_week
      t.decimal :irr_past_month
      t.decimal :perp_over_spot
      t.decimal :spot_over_perp

      t.timestamps
    end
  end
end
