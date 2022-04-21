class SubAccount < ApplicationRecord
  belongs_to :user

  validates_presence_of :user_id, :name, :application, :encrypted_public_key, :encrypted_secret_key, message: "欄位不能為空"

  validates_uniqueness_of :name, :scope => :user_id, message: "子帳號名稱重複"
  validates_uniqueness_of :application, :scope => :user_id, message: "已有 %{value} API 設定"

  validates_inclusion_of :application, :in => APPNAMES
  
  def crypt
    ActiveSupport::MessageEncryptor.new(Rails.application.secrets.secret_key_base[0..31])
  end

  def display_key
    raw_key = self.crypt.decrypt_and_verify(self[:encrypted_public_key])
    hidden_length = raw_key.length - 5 

    output = "*" * hidden_length + raw_key[-5,5] if hidden_length > 0
  end

  def ftx_api_validation?
    ftx_errors = {
      "cancel" => FtxClient.cancel_order(self, 1)["error"], # the number 1 stands for choosen random order_id in ftx
      "withdrawals" => FtxClient.withdrawals_for_validation(self)["error"]
    }

    return error_msg_filter(ftx_errors)["error"].empty?
  end

private
  def error_msg_filter(ftx_errors)
    expected_errors = {"cancel" => "Order not found", "withdrawals" => "Not allowed with withdrawal-disabled permissions"}

    return {"error" => "API have no permissions for subaccount #{self.name}"} if ftx_errors["cancel"][0..35] == "Only have permissions for subaccount"
    expected_errors.each {|k,v| return {"error" => ftx_errors[k]} unless ftx_errors[k] == v }
    return {"error" => ""}
  end
end
