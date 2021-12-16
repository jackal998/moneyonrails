class AddNicknameToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :nickname, :string

    add_column :users, :encrypted_fund_pub, :string
    add_column :users, :encrypted_fund_pub_iv, :string
    add_column :users, :encrypted_fund_sec, :string
    add_column :users, :encrypted_fund_sec_iv, :string

    add_column :users, :encrypted_grid_pub, :string
    add_column :users, :encrypted_grid_pub_iv, :string
    add_column :users, :encrypted_grid_sec, :string
    add_column :users, :encrypted_grid_sec_iv, :string

    add_index :users, :nickname, unique: true
    
    add_index :users, :encrypted_fund_pub, unique: true
    add_index :users, :encrypted_fund_pub_iv, unique: true
    add_index :users, :encrypted_fund_sec, unique: true
    add_index :users, :encrypted_fund_sec_iv, unique: true

    add_index :users, :encrypted_grid_pub, unique: true
    add_index :users, :encrypted_grid_pub_iv, unique: true
    add_index :users, :encrypted_grid_sec, unique: true
    add_index :users, :encrypted_grid_sec_iv, unique: true
  end
end
