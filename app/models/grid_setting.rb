class GridSetting < ApplicationRecord
  belongs_to :coin
  has_many :grid_orders
end
