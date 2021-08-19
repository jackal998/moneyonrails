class CreateGridSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :grid_settings do |t|
      t.integer :coin_id, :index => true
      t.string :coin_name, :index => true

      t.decimal :lower_limit
      t.boolean :dyn_lower_limit, default: false

      t.decimal :upper_limit
      t.boolean :dyn_upper_limit, default: false

      t.integer :girds
      t.decimal :grid_gap
      t.boolean :constant_gap, default: true

      t.decimal :input_USD_amount
      t.decimal :input_spot_amount
      t.decimal :input_totalUSD_amount

      t.decimal :trigger_price
      t.decimal :stop_loss_price
      t.decimal :take_profit_price

      t.decimal :threshold, default: 0.00

      t.string :status, default: "waiting", :index => true

      t.timestamps
    end
  end
end
