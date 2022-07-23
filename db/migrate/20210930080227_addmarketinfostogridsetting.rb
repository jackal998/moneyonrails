class Addmarketinfostogridsetting < ActiveRecord::Migration[6.1]
  def change
    add_column :grid_settings, :price_step, :decimal
    add_column :grid_settings, :size_step, :decimal
  end
end
