class AddIndexUserOnFundingStats < ActiveRecord::Migration[6.1]
  def change
    add_index :funding_stats, :user_id
  end
end
