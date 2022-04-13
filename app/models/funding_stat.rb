class FundingStat < ApplicationRecord
  validates_uniqueness_of :coin_name
  belongs_to :user
end
