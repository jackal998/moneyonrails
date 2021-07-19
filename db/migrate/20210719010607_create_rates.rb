class CreateRates < ActiveRecord::Migration[6.1]
  def change
    create_table :rates do |t|

      t.string :name, :index => true
      t.datetime :time
      t.decimal :rate
      t.integer :coin_id, :index => true

      t.timestamps
    end
  end
end
