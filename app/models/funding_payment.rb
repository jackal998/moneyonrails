class FundingPayment < ApplicationRecord
  belongs_to :coin
  belongs_to :user

  validates_uniqueness_of :time, scope: [:coin_name, :user_id]
end
