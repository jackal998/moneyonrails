class CreateFundingOrders < ActiveRecord::Migration[6.1]
  def change
    create_table :funding_orders do |t|
      t.integer :coin_id, :index => true
      t.string :coin_name, :index => true

      t.decimal :original_coin_amount
      t.decimal :original_perp_amount
      t.decimal :target_coin_amount
      t.decimal :target_perp_amount

      t.string :order_status, default: "close", :index => true

      t.integer :acceleration, default: 1

      t.decimal :threshold, default: 0.00

      t.timestamps
    end
  end
end
