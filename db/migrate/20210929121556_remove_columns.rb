class RemoveColumns < ActiveRecord::Migration[6.1]
  def change
    remove_column :grid_orders, :coin_id
    remove_column :grid_orders, :coin_name

    remove_column :grid_settings, :coin_id
    remove_column :grid_settings, :coin_name

    add_column :grid_orders, :market_name, :string
    add_column :grid_settings, :market_name, :string
  end
end
