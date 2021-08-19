class AddColumnToCoin < ActiveRecord::Migration[6.1]
  def change

    add_column :coins, :spotpriceIncrement, :decimal
    add_column :coins, :spotsizeIncrement, :decimal

    rename_column :coins, :priceIncrement, :perppriceIncrement
    rename_column :coins, :sizeIncrement, :perpsizeIncrement
    
  end
end
