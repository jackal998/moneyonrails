class Coin < ApplicationRecord
  has_many :rates
  has_many :funding_orders
  has_many :funding_payments
  has_one :current_fund_stat
  
  attribute :weight, default: 0.00
  
  validates_uniqueness_of :name, :message => "coin name can not be same"


  def self.to_csv
    require'csv'
    file = "#{Rails.root}/public/coin_data.csv"
    coins = Coin.order(:name)
    headers = ["id","name","weight", "have_perp","priceIncrement","sizeIncrement","minProvideSize"]

    CSV.open(file, 'w', write_headers: true, headers: headers) do |writer|
      coins.each do |coin| 
        writer << [coin.id,coin.name,coin.weight,coin.have_perp,coin.priceIncrement,coin.sizeIncrement,coin.minProvideSize] 
      end
    end
  end
end 