class GridOrder < ApplicationRecord
  belongs_to :grid_setting
  belongs_to :user
end
