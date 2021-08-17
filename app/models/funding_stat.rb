class FundingStat < ApplicationRecord
  validates_uniqueness_of :coin_name
end
