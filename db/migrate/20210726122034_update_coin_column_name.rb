class UpdateCoinColumnName < ActiveRecord::Migration[6.1]
  def change
    rename_column :coins, :min_amount, :minProvideSize
    add_column :coins, :priceIncrement, :decimal
    add_column :coins, :sizeIncrement, :decimal
  end
end
