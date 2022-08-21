class AddUniqUserCoinNameOnFundingStats < ActiveRecord::Migration[6.1]
  def change
    add_index :funding_stats, [:user_id, :coin_name], unique: true
  end
end
