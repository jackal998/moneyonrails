class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :timeoutable

  has_many :funding_orders
  has_many :funding_payments
  has_many :funding_stats
  has_many :grid_orders
  has_many :grid_settings
end
