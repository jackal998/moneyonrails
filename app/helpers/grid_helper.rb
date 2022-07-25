module GridHelper
  def decimals(a)
    num = 0
    while a != a.to_i
      num += 1
      a *= 10
    end
    num
  end

  def profit_helper(grid_setting, grid_profits)
    profit = {}
    grid_profit = grid_profits[grid_setting.id]
    totalUSD = grid_setting.input_totalUSD_amount

    [:grid, :spot, :total].each do |item|
      profit[item] = grid_profit[item] > 0 ? {value: "+", percent: "+", color: "text-success"} : {value: "", percent: "", color: "text-danger"}

      profit[item][:value] += grid_profit[item].round(2).to_s
      profit[item][:percent] += (grid_profit[item] / totalUSD * 100).round(2).to_s
    end

    profit
  end
end
