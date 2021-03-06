class GridController < ApplicationController
  require "ftx_client"

  def index
    market_name = index_params["market_name"] || ("#{index_params["coin_name"]}/USD" if index_params["coin_name"]) || GridSetting.last["market_name"]

    @market = FtxClient.market_info(market_name)["result"]
    coin_name = @market["type"] == "spot" ? @market["baseCurrency"] : nil

    @grid_setting = GridSetting.new(market_name: market_name, price_step: @market["priceIncrement"], size_step: @market["sizeIncrement"])
    @grid_settings = GridSetting.includes(:grid_orders).order("grid_orders.price asc").where(status: ["active", "closing"])

    grid_profits = {}
    @grid_settings.each { |g| grid_profits[g.id] = profit(g) }

    balances = ftx_wallet_balance("GridOnRails", coin_name)

    render locals: {balances: balances, coin_name: coin_name, tv_market_name: tv_market_name(market_name), grid_profits: grid_profits}
  end

  def creategrid
    @grid_setting = GridSetting.new(creategrid_params)
    input_totalUSD_amount = (@grid_setting["input_spot_amount"] * @grid_setting["trigger_price"] + @grid_setting["input_USD_amount"]).round(2)
    @grid_setting.attributes = {status: "new", input_totalUSD_amount: input_totalUSD_amount}
    @grid_setting.save

    GridExecutorJob.perform_later(is_main_job: true, grid_setting_id: @grid_setting[:id])
    redirect_to grid_path(market_name: @grid_setting[:market_name])
  end

  def closegrid
    @grid_setting = GridSetting.find(params["grid_setting"]["id"])
    @grid_setting.update(status: "closing") unless @grid_setting.status == "closed"

    close_price = @grid_setting["id"] * @grid_setting["price_step"]
    payload = {market: @grid_setting[:market_name], side: "buy", price: close_price, type: "limit", size: @grid_setting["order_size"]}

    order_result = FtxClient.place_order("GridOnRails", payload)["result"]
    puts "closegrid order result:" + order_result.select { |k, v| {k => v} if ["market", "side", "price", "size", "status", "createdAt"].include?(k) }.to_s

    redirect_to grid_path(market_name: @grid_setting[:market_name])
  end

  private

  def profit(grid_setting)
    market_name = grid_setting["market_name"]
    @market = FtxClient.market_info(market_name)["result"]
    market_price = @market["price"]

    lower_value, gap_value, size_value = grid_setting["lower_limit"], grid_setting["grid_gap"], grid_setting["order_size"]

    trigger_price_on_grid = ((grid_setting["trigger_price"] - lower_value) / gap_value).round(0) * gap_value + lower_value
    market_price_on_grid = ((market_price - lower_value) / gap_value).round(0) * gap_value + lower_value

    open_grids = []
    buy_orders, sell_orders = 0, 0
    grid_setting.grid_orders.each do |order|
      if ["new", "open"].include?(order.status)
        open_grids << order["price"]
        market_price_on_grid += market_price > market_price_on_grid ? gap_value : - gap_value if order["price"] == market_price_on_grid
      elsif ["closed"].include?(order.status)
        next if order.filledSize != size_value
        order.side == "buy" ? buy_orders += 1 : sell_orders += 1
      end
    end

    buy_grid_prices, sell_grids = 0, 0
    open_grids.each do |price|
      market_price_on_grid > price ? buy_grid_prices += price : sell_grids += 1
    end

    current_grid = (market_price_on_grid - trigger_price_on_grid) / gap_value
    unless current_grid == 0
      current_grid > 0 ? sell_orders -= current_grid : buy_orders += current_grid
    end

    # ??????????????????????????????????????????????????????????????????limit closed orders, ???????????????????????????max?????????...
    grid_profit = [sell_orders, buy_orders].max * gap_value * grid_setting["order_size"]
    # ????????????(???????????????????????????) = ??????????????? = USD ?????? (buy_grids(sum prices) * size) + Spot ?????? (sell_grids * size * market_price)
    # ??????????????????input_totalUSD_amount??????????????????
    spot_profit = (buy_grid_prices + sell_grids * market_price) * size_value - grid_setting["input_totalUSD_amount"]
    total_profit = grid_profit + spot_profit

    {grid: grid_profit, spot: spot_profit, total: total_profit}
  end

  def tv_market_name(ftx_market_name)
    ftx_market_name.dup.sub!("-", "") || ftx_market_name.dup.sub!("/", "")
  end

  def creategrid_params
    params.require(:grid_setting).permit(:market_name, :order_size, :price_step, :size_step,
      :lower_limit, :upper_limit, :grids, :grid_gap,
      :input_USD_amount, :input_spot_amount,
      :trigger_price, :threshold,
      :stop_loss_price, :take_profit_price)
  end

  def index_params
    params.permit(:coin_name, :market_name)
  end
end
