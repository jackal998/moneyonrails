class CreateGridOrders < ActiveRecord::Migration[6.1]
  def change
    create_table :grid_orders do |t|
      t.integer :coin_id, :index => true
      t.string :coin_name, :index => true

      t.integer :grid_setting_id, :index => true
      t.decimal :ftx_order_id, :index => true, :unique => true

      t.string :market, default: ""
      t.string :order_type, default: ""
      t.string :side, default: ""
      t.decimal :price
      t.decimal :size
      t.string :status, default: "new", :index => true
      t.decimal :filledSize
      t.decimal :remainingSize
      t.decimal :avgFillPrice
      t.datetime :createdAt
      
      t.timestamps
    end
  end
end
