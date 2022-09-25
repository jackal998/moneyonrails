class AddUseridToTables < ActiveRecord::Migration[6.1]
  def change
    add_column :funding_orders, :user_id, :integer, index: true
    add_column :funding_payments, :user_id, :integer, index: true
    add_column :funding_stats, :user_id, :integer, index: true
    add_column :grid_orders, :user_id, :integer, index: true
    add_column :grid_settings, :user_id, :integer, index: true
  end
end
