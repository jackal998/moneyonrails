class AddIndexToCoins < ActiveRecord::Migration[6.1]
  def change
    add_index :coins, :name, unique: true
  end
end
