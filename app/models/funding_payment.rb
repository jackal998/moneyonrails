class FundingPayment < ApplicationRecord
  belongs_to :coin
  belongs_to :user
  
  validates_uniqueness_of :coin_name, :scope => :time
end
