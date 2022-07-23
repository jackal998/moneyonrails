class Columnaddindex < ActiveRecord::Migration[6.1]
  def change
    add_index :grid_orders, :market_name
    add_index :grid_settings, :market_name
  end
end
