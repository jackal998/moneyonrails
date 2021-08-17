class FundingPayment < ApplicationRecord
  belongs_to :coin
  
  validates_uniqueness_of :coin_name, :scope => :time
end
