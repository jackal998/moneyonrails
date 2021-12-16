class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :rememberable, :validatable
  
  attr_encrypted :fund_pub, key: Rails.application.credentials.encrypted_key[:fund][:pub]
  attr_encrypted :fund_sec, key: Rails.application.credentials.encrypted_key[:fund][:sec]
  attr_encrypted :grid_pub, key: Rails.application.credentials.encrypted_key[:grid][:pub]
  attr_encrypted :grid_sec, key: Rails.application.credentials.encrypted_key[:grid][:sec]

  def normal?
    self.role == "normal"
  end
end
