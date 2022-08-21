class Remove60StatAndRenameHistoricalTo365OnFundingStats < ActiveRecord::Migration[6.1]
  def change
    remove_column :funding_stats, :last_60_day_payments
    remove_column :funding_stats, :last_60_day_irr

    rename_column :funding_stats, :historical_payments, :last_365_day_payments
    rename_column :funding_stats, :historical_irr, :last_365_day_irr
  end
end
