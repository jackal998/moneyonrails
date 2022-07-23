class AddSystemDescriptionToFundingOrder < ActiveRecord::Migration[6.1]
  def change
    add_column :funding_orders, :system, :boolean, default: false
    add_column :funding_orders, :description, :string
    add_index :funding_orders, :system
    rename_column :funding_orders, :original_coin_amount, :original_spot_amount
    rename_column :funding_orders, :target_coin_amount, :target_spot_amount
  end
end
