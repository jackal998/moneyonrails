class AddSubaccountNamesUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :account_fund, :string
    add_column :users, :account_grid, :string
  end
end
