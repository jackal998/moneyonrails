class Rate < ApplicationRecord
  belongs_to :coin

  validates_uniqueness_of :name, scope: :time
end
