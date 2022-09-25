class RenamePermissionToFundToPermissionToFundingInUsers < ActiveRecord::Migration[6.1]
  def change
    rename_column :users, :permission_to_fund, :permission_to_funding
  end
end
