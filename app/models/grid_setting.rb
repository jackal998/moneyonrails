class GridSetting < ApplicationRecord
  has_many :grid_orders
  belongs_to :user

  def params_check?
    return false unless ["active", "new"].include?(self["status"])
    
    check_value = {}
    ["upper_limit", "lower_limit", "grids", "grid_gap", "price_step"].each do |item|
      next if self[item]
      error_msg = item + ": #{self[item]} value invalid."
      self.update(status: "#{item}_error", description: error_msg)
      return false
    end

    upper_limit, lower_limit = self["upper_limit"], self["lower_limit"]
    grids, grid_gap = self["grids"], self["grid_gap"]
    price_step = self["price_step"]

    check_value["grids"] = ((self["upper_limit"] - self["lower_limit"]) / self["price_step"] + 1)
    check_value["grid_gap"] = (((self["upper_limit"] - self["lower_limit"]) / self["price_step"]) / (self["grids"] - 1)).round(0) * self["price_step"]
    check_value["upper_limit"] = self["lower_limit"] + ((self["grids"] - 1) * self["grid_gap"])

    ["grids","grid_gap","upper_limit"].each do |item|
      compare_sym = ""
      case item
      when "grids"
        compare_sym = ">" if self[item] > check_value[item]
      else
        compare_sym = "!=" if self[item] != check_value[item]
      end

      unless compare_sym == ""
        error_msg = item + ": #{self[item]} #{compare_sym} check_value: #{check_value[item]}, invalid."
        self.update(status: "#{item}_error", description: error_msg)
        return false
      end
    end

    return true
  end
end
