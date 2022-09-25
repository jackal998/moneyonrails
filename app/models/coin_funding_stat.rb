class CoinFundingStat < ApplicationRecord
  belongs_to :coin

  validates_uniqueness_of :coin_id
end
