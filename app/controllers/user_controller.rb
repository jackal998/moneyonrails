class UserController < ApplicationController
  def show
    @sub_account = SubAccount.new(user: current_user)
    @sub_accounts = SubAccount.select("id", "name", "application", "encrypted_public_key").where("user_id = ?", current_user)
    @sub_accounts.each { |sa| sa[:encrypted_public_key] = sa.display_key}
  end

  def createsubaccount
    @sub_account = SubAccount.new(createsubaccount_params)

    [:encrypted_public_key, :encrypted_secret_key].each do |k|
      @sub_account[k] = @sub_account.crypt.encrypt_and_sign(@sub_account[k])
    end
    
    if @sub_account.ftx_api_validation?
      @sub_account.save
    else
      @sub_account.errors.add(:api, "API設定不正確")
    end

    flash_msg = error_message_helper(@sub_account.errors.messages)
    redirect_to authenticated_root_path, flash: { alert: flash_msg }
  end

  def deletesubaccount
    @sub_account = SubAccount.where("user_id = ?", current_user).find(deletesubaccount_params["id"])
    
    @sub_account.delete if @sub_account

    flash_msg = error_message_helper(@sub_account.errors.messages)
    redirect_to authenticated_root_path, flash: { alert: flash_msg }
  end

private
  def deletesubaccount_params
    params.require(:sub_account).permit(:id, :user_id)
  end

  def createsubaccount_params
    params.require(:sub_account).permit(:name, :application, :user_id, :encrypted_public_key, :encrypted_secret_key)
  end

  def error_message_helper(messages={})
    return nil unless messages.present?
    messages.map{|k,v| v}
  end
end
