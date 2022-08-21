class FundingStat < ApplicationRecord
  belongs_to :user

  validates_uniqueness_of :coin_name, scope: [:user_id]

  DISPLAY_PERIODS = [365, 90, 30, 14, 7, 3, 1]
end
