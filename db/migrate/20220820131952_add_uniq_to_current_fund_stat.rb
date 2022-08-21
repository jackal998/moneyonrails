class AddUniqToCurrentFundStat < ActiveRecord::Migration[6.1]
  def change
    remove_index :current_fund_stats, :coin_id
    add_index :current_fund_stats, :coin_id, unique: true
  end
end
