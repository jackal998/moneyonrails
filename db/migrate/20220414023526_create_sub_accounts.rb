class CreateSubAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :sub_accounts do |t|
      t.integer :user_id,             null: false, :index => true
      t.string :name,                 null: false, default: ""
      t.string :application,          null: false, default: ""
      t.string :encrypted_public_key, null: false, default: ""
      t.string :encrypted_secret_key, null: false, default: ""

      t.timestamps
    end
  end
end
