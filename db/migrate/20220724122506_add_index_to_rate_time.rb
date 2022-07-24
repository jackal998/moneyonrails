class AddIndexToRateTime < ActiveRecord::Migration[6.1]
  def change
    add_index :rates, :time
    add_index :rates, [:time, :coin_id]
  end
end
