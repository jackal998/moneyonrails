class CreateRates < ActiveRecord::Migration[6.1]
  def change
    create_table :rates do |t|

      t.string :name
      t.datetime :time
      t.decimal :rate

      t.timestamps
    end
  end
end
