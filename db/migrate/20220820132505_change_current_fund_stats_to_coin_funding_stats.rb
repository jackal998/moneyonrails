class ChangeCurrentFundStatsToCoinFundingStats < ActiveRecord::Migration[6.1]
  def change
    rename_table :current_fund_stats, :coin_funding_stats
  end
end
