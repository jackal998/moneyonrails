class AddStatusToCoins < ActiveRecord::Migration[6.1]
  def change
    add_column :coins, :status, :string, index: true, default: "active", null: false
  end
end
