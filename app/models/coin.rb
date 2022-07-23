class Coin < ApplicationRecord
  self.filter_attributes = []

  has_many :rates
  has_one :latest_rate, -> { Rate.latest_rates_for_coins }, class_name: "Rate"

  has_many :funding_orders
  has_many :funding_payments
  has_one :current_fund_stat

  attribute :weight, default: 0.00

  validates_uniqueness_of :name, message: "coin name can not be same"
end
