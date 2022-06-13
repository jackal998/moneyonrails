class UserController < ApplicationController
  def show
    @sub_accounts = current_user.sub_accounts

    @sub_account = SubAccount.new(user: current_user) if @sub_accounts.size < ROBOT.size
  
    @sub_accounts.each do |sub_account|
      sub_account[:encrypted_public_key] = sub_account.display_key
      sub_account[:encrypted_secret_key] = "[FILTERED]"
    end

  end

  def createsubaccount
    @sub_account = SubAccount.new(createsubaccount_params)

    [:encrypted_public_key, :encrypted_secret_key].each do |k|
      @sub_account[k] = @sub_account.crypt.encrypt_and_sign(@sub_account[k])
    end
    
    if @sub_account.ftx_api_validation?
      @sub_account.save
      current_user.send("#{@sub_account.application}_account=", @sub_account)
    else
      @sub_account.errors.add(:api, "請確認API之權限設定或是子帳號名稱是否正確")
    end

    flash_msg = error_message_helper(@sub_account.errors.messages)
    redirect_to authenticated_root_path, flash: { alert: flash_msg }
  end

  def deletesubaccount
    @sub_account = SubAccount.where("user_id = ?", current_user).find(deletesubaccount_params["id"])
    
    if @sub_account
      current_user.send("#{@sub_account.application}_account=", nil)
      @sub_account.delete
    end

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
