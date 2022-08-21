class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable, :timeoutable

  scope :can_funding, -> { where.not(permission_to_funding: "false") }
  scope :can_grid, -> { where.not(permission_to_grid: "false") }

  has_many :funding_orders
  has_many :funding_payments
  has_many :funding_stats
  has_many :grid_orders
  has_many :grid_settings
  has_many :sub_accounts

  after_initialize :set_sub_accounts

  attr_accessor :funding_account
  attr_accessor :grid_account

  def set_sub_accounts
    ROBOT.each do |name, data|
      sub_accounts.each { |sub_account| send("#{name}_account=", sub_account) if sub_account.application == name }
    end
  end
end
