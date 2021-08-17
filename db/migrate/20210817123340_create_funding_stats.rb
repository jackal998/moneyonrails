class CreateFundingStats < ActiveRecord::Migration[6.1]
  def change
    create_table :funding_stats do |t|
      t.integer :coin_id, :index => true
      t.string :coin_name, :index => true

      t.decimal :last_1_day_payments, default: 0
      t.decimal :last_1_day_irr, default: 0
      t.decimal :last_3_day_payments, default: 0
      t.decimal :last_3_day_irr, default: 0
      t.decimal :last_7_day_payments, default: 0
      t.decimal :last_7_day_irr, default: 0
      t.decimal :last_14_day_payments, default: 0
      t.decimal :last_14_day_irr, default: 0
      t.decimal :last_30_day_payments, default: 0
      t.decimal :last_30_day_irr, default: 0
      t.decimal :last_60_day_payments, default: 0
      t.decimal :last_60_day_irr, default: 0
      t.decimal :last_90_day_payments, default: 0
      t.decimal :last_90_day_irr, default: 0
      t.decimal :historical_payments, default: 0
      t.decimal :historical_irr, default: 0

      t.timestamps
    end
  end
end
