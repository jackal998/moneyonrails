class CreateFundingPayments < ActiveRecord::Migration[6.1]
  def change
    create_table :funding_payments do |t|
      t.integer :coin_id, index: true
      t.string :coin_name, index: true

      t.decimal :payment
      t.datetime :time, index: true
      t.decimal :rate

      t.timestamps
    end
  end
end
