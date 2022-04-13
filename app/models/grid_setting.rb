class GridSetting < ApplicationRecord
  has_many :grid_orders
  belongs_to :user
end
