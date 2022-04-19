class SubAccount < ApplicationRecord
  belongs_to :user

  validates_presence_of :user_id, :name, :application, :encrypted_public_key, :encrypted_secret_key, message: "欄位不能為空"

  validates_uniqueness_of :name, :scope => :user_id, message: "子帳號名稱重複"
  validates_uniqueness_of :application, :scope => :user_id, message: "已有 %{value} API 設定"

  validates_inclusion_of :application, :in => ["Funding", "Grid"]
end
