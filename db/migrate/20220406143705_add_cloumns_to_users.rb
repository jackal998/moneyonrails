class AddCloumnsToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :name, :string

    add_column :users, :permission_to_fund, :string, null: false, default: "false"
    add_column :users, :permission_to_grid, :string, null: false, default: "false"
  end
end
