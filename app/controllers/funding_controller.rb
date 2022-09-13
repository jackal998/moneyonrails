class FundingController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_for_funding
  before_action :set_coin_and_coins, only: [:index, :show]

  LINE_CHART_START_TIME = Time.now - 6.weeks

  def index
    fundingpayments = FundingPayment
      .where("time > ?", 30.day.ago)
      .where("user_id = ?", current_user)
      .group(:coin_name)
      .group_by_day(:time, format: "%F")
      .sum(:payment)
      .each_with_object({}) do |((coin_name, date), payment), h|
        h[coin_name] ||= {}
        h[coin_name][date] = payment
      end

    list_index = []
    @col_chart_payment_data = []
    @pie_chart_payment_data = []

    fundingpayments.each_with_index do |(coin_name, payments), index|
      list_index << coin_name
      @col_chart_payment_data << {name: coin_name, data: []}
      @pie_chart_payment_data << [coin_name, 0]

      payments.each do |date, payment|
        @col_chart_payment_data[index][:data] << [date, (0 - payment)]
        @pie_chart_payment_data[index][1] += (0 - payment)
      end
    end

    @pie_chart_payment_data.delete_if { |(_coin_name, payment)| payment < 0.000001 }

    @fundingstats = FundingStat.all

    balances = ftx_wallet_balance(current_user.funding_account, selected_coin)

    render locals: {balances: balances, list_index: list_index}
  end

  def show
    @funding_orders = FundingOrder.includes(coin: :coin_funding_stat).belongs_to_user(current_user)

    @underway_order = @funding_orders.detect { |funding_order| funding_order[:order_status] == "Underway" }

    @positions = FtxClient.account(current_user.funding_account)["result"]["positions"].each_with_object({}) do |position, h|
      next if position["netSize"] == 0

      position_coin_name, _ = position["future"].split("-")
      precision =
        helpers.decimals(@coins.detect { |coin| coin[:name] == position_coin_name }.values_at([:spotsizeIncrement, :perpsizeIncrement]).max)

      h[position_coin_name] = {
        "precision" => precision,
        **position.slice("netSize", "cost")
      }
    end
    @positions[selected_coin] ||= {"netSize" => 0, "cost" => 0}

    @fund_stat = @coin.coin_funding_stat
    @fundingstats = current_user.funding_stats

    @line_chart_data = @coin.rates.where("time > ?", LINE_CHART_START_TIME).order("time asc").map { |r| [r.time.strftime("%m/%d %H:%M"), r.rate * 100] }
    @zeros = @line_chart_data.map { |t, _| [t, 0] }

    @ftx_account = FtxClient.account(current_user.funding_account)

    balances = ftx_wallet_balance(current_user.funding_account, selected_coin)
    @pie_chart_balances_data = balances.map { |coin_name, value| [coin_name, value["usdValue"].round(2)] if coin_name != "totalusdValue" && value["usdValue"] > 0.001 }.compact

    @funding_order = FundingOrder.new(
      coin: @coin,
      coin_name: @coin.name,
      user: current_user,
      original_spot_amount: balances[selected_coin]["spot_amount"],
      original_perp_amount: @positions[selected_coin]["netSize"]
    )

    days_to_show = [1, 3, 7, 14, 30] # ,60,90,:historical]

    render locals: {balances: balances, days_to_show: days_to_show}
  end

  def createorder
    @funding_order = FundingOrder.new(createorder_params)

    if @funding_order.target_perp_amount && @funding_order.target_perp_amount != @funding_order.original_perp_amount
      @funding_order["order_status"] = "Underway"

      @funding_order.save
      OrderExecutorJob.perform_later(@funding_order.id)

      redirect_to funding_show_path(coin_name: @funding_order.coin_name)
    end
  end

  def abortorder
    @funding_order = FundingOrder.find(params["funding_order"]["id"])
    @funding_order.update(order_status: "Abort") if @funding_order.order_status == "Underway"

    # 如果order_status有問題，要顯示出來
    redirect_to funding_show_path(coin_name: params["current_coin_name"])
  end

  private

  def set_coin_and_coins
    @coins = case action_name
    when "index"
      Coin.active.with_perp.include_funding_stat
    when "show"
      Coin.active.select("coins.name", "coins.spotsizeIncrement", "coins.perpsizeIncrement", "coins.weight").include_funding_stat
    end

    @coin = @coins.detect { |coin| coin[:name] == selected_coin }
  end

  def selected_coin
    params["coin_name"] || "BTC"
  end

  def createorder_params
    params.require(:funding_order).permit(:coin_id, :coin_name, :user_id,
      :original_spot_amount, :original_perp_amount,
      :target_spot_amount, :target_perp_amount,
      :acceleration, :threshold)
  end
end
