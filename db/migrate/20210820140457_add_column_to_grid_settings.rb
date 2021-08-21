class AddColumnToGridSettings < ActiveRecord::Migration[6.1]
  def change
    add_column :grid_settings, :order_size, :decimal
  end
end
