class FundingController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_for_funding

  def index
    # should move to rake
    # helpers.update_market_infos
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
    
    coin_name = params["coin_name"] || "BTC"
    @coin = @coins.detect { |coin| coin[:name] == coin_name }

    list_index = {}
    li = 0
    balances = ftx_wallet_balance(current_user.funding_account, coin_name)

    @col_chart_payment_data = []
    @pie_chart_payment_data = []

    balances.each do |k,v| 
      if k != "totalusdValue" && v["usdValue"] > 0.001 && k != "USD"
        list_index[k] = li
        @col_chart_payment_data << {name: k, data:[]}
        @pie_chart_payment_data << [k, 0]
        li += 1
      end
    end

    fundingpayments = FundingPayment.where("time > ?", 30.day.ago).where("user_id = ?", current_user).group(:coin_name).group_by_day(:time, format: '%F').sum(:payment)
    @fundingstats = FundingStat.all

    coin_name = ""
    fundingpayments.each do |coin_day, payment|
      # coin_day = ["BAO", "2021-08-18"]
      if coin_name != coin_day[0]
        coin_name = coin_day[0]
        unless list_index[coin_name]
          list_index[coin_name] = list_index.size
          @col_chart_payment_data << {name: coin_name, data: []}
          @pie_chart_payment_data << [coin_name, 0]
        end
      end

      @pie_chart_payment_data[list_index[coin_name]][1] += (0 - payment)
      @col_chart_payment_data[list_index[coin_name]][:data] << [coin_day[1], (0 - payment)]
    end
    
    @pie_chart_payment_data.delete_if do |data|
      next if data[1] >= 0.01
      coin_name = data[0]
      list_index.except!(coin_name)
      @col_chart_payment_data.delete_if {|dataset| dataset[:name] == coin_name }
    end

    render locals: {balances: balances, list_index: list_index}
  end

  def show
    @coins = Coin.select("coins.name", "coins.spotsizeIncrement", "coins.perpsizeIncrement", "coins.weight").includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
    
    coin_name = params["coin_name"] ? params["coin_name"] : "BTC"
    @coin = @coins.detect { |coin| coin[:name] == coin_name }

    @funding_orders = FundingOrder.includes(coin: :current_fund_stat).where(system: false).where("user_id = ?", current_user).order("created_at desc")
    
    @underway_order = @funding_orders.detect { |funding_order| funding_order[:order_status] == "Underway" }
    # 如果order_status有問題，要顯示出來

    @positions = {coin_name => {"netSize" => 0, "cost" => 0}}
    FtxClient.account(current_user.funding_account)["result"]["positions"].each do |position|
      next if position["netSize"] == 0

      p_coin_name = position["future"].split("-")[0]
      p_coin = @coins.detect { |coin| coin[:name] == p_coin_name }
      precision = helpers.decimals(p_coin[:spotsizeIncrement] > p_coin[:perpsizeIncrement] ? p_coin[:spotsizeIncrement] : p_coin[:perpsizeIncrement])

      @positions[position["future"].split("-")[0]] = {
          "netSize" => position["netSize"],
          "cost" => position["cost"],
          "precision" => precision}
    end
    days_to_show = [1,3,7,14,30] #,60,90,:historical]

    @fund_stat = @coin.current_fund_stat
    @fundingstats = FundingStat.where("user_id = ?", current_user)

    @line_chart_data = @coin.rates.where("time > ?", Time.now - 6.weeks).order("time asc").map { |r| [r.time.strftime('%m/%d %H:%M'),r.rate*100]}
    @zeros = @line_chart_data.map { |t,r| [t,0] }

    @ftx_account = FtxClient.account(current_user.funding_account)
    balances = ftx_wallet_balance(current_user.funding_account, coin_name)

    @pie_chart_balances_data = []
    
    balances.each do |k,v| 
      @pie_chart_balances_data << [k, v["usdValue"].round(2)] if k != "totalusdValue" && v["usdValue"] > 0.001
    end

    @funding_order = FundingOrder.new(
      :coin_id => @coin.id, 
      :coin_name => coin_name,
      :user_id => current_user.id,
      :original_spot_amount => balances[coin_name]["spot_amount"],
      :original_perp_amount => @positions[coin_name]["netSize"]
      )

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
    @funding_order.update(:order_status => "Abort") if @funding_order.order_status == "Underway"
    
    # 如果order_status有問題，要顯示出來
    redirect_to funding_show_path(coin_name: params["current_coin_name"])
  end

private
  def createorder_params
    params.require(:funding_order).permit(:coin_id,:coin_name,:user_id,
                                          :original_spot_amount,:original_perp_amount,
                                          :target_spot_amount,:target_perp_amount,
                                          :acceleration,:threshold)
  end
end