class FundingOrder < ApplicationRecord
  scope :belongs_to_user, ->(user) { where(system: false, user: user) }

  belongs_to :coin
  belongs_to :user
end
