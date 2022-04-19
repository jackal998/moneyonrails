class UserController < ApplicationController
  def show
    @sub_account = SubAccount.new(user: current_user)
    @sub_accounts = SubAccount.select("id", "name", "application", "encrypted_public_key").where("user_id = ?", current_user)
    @sub_accounts.each { |sa| sa[:encrypted_public_key] = display_key(sa[:encrypted_public_key])}
  end

  def createsubaccount
    @sub_account = SubAccount.new(createsubaccount_params)

    [:encrypted_public_key, :encrypted_secret_key].each do |k|
      @sub_account[k] = crypt.encrypt_and_sign(@sub_account[k])
    end

    @sub_account.save
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

  def crypt
    ActiveSupport::MessageEncryptor.new(Rails.application.secrets.secret_key_base[0..31])
  end

  def display_key(encrpyed_key)
    raw_key = crypt.decrypt_and_verify(encrpyed_key)
    hidden_length = raw_key.length - 5 

    output = "*" * hidden_length + raw_key[-5,5] if hidden_length > 0
  end

  def error_message_helper(messages={})
    return nil unless messages.present?
    messages.map{|k,v| v}
  end
end
