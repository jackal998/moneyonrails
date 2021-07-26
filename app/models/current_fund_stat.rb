class CurrentFundStat < ApplicationRecord
  belongs_to :coin

  def data_calc_ready?
    return true if self.market_type == "fs" || self.market_type == "sf"
    return false
  end

end
