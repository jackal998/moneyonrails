class CreateCoins < ActiveRecord::Migration[6.1]
  def change
    create_table :coins do |t|

      t.string :name
      t.decimal :weight
      t.decimal :min_amount
      t.boolean :have_perp

      t.timestamps
    end
  end
end
