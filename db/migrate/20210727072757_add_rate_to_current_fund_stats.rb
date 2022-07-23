class AddRateToCurrentFundStats < ActiveRecord::Migration[6.1]
  def change
    add_column :current_fund_stats, :rate, :decimal
  end
end
