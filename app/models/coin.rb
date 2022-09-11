class Coin < ApplicationRecord
  self.filter_attributes = []

  scope :with_perp, -> { where(have_perp: true) }
  scope :active, -> { where(status: "active") }

  has_many :rates
  has_many :sorted_rates, -> { order("time asc") }, class_name: "Rate"
  has_many :funding_orders
  has_many :funding_payments
  has_one :coin_funding_stat

  attribute :weight, default: 0.00

  validates_uniqueness_of :name, message: "coin name can not be same"

  def latest_rate
    sorted_rates.last
  end

  def self.to_csv
    require "csv"
    file = "#{Rails.root}/public/coin_data.csv"
    coins = Coin.order(:name)
    headers = ["id", "name", "weight", "have_perp", "spotpriceIncrement", "spotsizeIncrement", "minProvideSize"]

    CSV.open(file, "w", write_headers: true, headers: headers) do |writer|
      coins.each do |coin|
        writer << [coin.id, coin.name, coin.weight, coin.have_perp, coin.spotpriceIncrement, coin.spotsizeIncrement, coin.minProvideSize]
      end
    end
  end
end
