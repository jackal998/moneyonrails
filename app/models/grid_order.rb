class GridOrder < ApplicationRecord
  belongs_to :coin
  belongs_to :grid_setting
end
