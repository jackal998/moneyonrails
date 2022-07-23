module FundingsHelper
  require "ftx_client"

  def decimals(a)
    num = 0
    while a != a.to_i
      num += 1
      a *= 10
    end
    num
  end
end
