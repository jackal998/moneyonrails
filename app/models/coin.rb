class Coin < ApplicationRecord
  has_many :rates

  validates_uniqueness_of :name, :message => "coin name can not be same"
end 