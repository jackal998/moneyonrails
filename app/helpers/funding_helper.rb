module FundingHelper
  def display_rate(r, n)
    return "" unless r
    "#{(r * 100).round(n)}%"
  end

  def decimals(a)
    num = 0
    while a != a.to_i
      num += 1
      a *= 10
    end
    num
  end

  def coin_balances_percent(balances, coin_name)
    balances["totalusdValue"] == 0 ? 0 : (balances[coin_name]["available_amount"] / balances["totalusdValue"]) * 100.round(0)
  end
end
