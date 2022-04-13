class FundingOrder < ApplicationRecord
  belongs_to :coin
  belongs_to :user
end
