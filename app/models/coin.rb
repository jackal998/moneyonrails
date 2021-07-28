class Coin < ApplicationRecord
  has_many :rates
  has_one :current_fund_stat
  
  attribute :weight, default: 0.00
  
  validates_uniqueness_of :name, :message => "coin name can not be same"
end 