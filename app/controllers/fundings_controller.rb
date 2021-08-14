class FundingsController < ApplicationController
  require 'ftx_client'
  def index
    helpers.update_market_infos if Time.now - CurrentFundStat.last.updated_at > 15
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
    @ftx_account = FtxClient.account

    list_index = {}
    li = 0
    balances = ftx_wallet_balance
    balances["USD"] = balances.delete("USD")
    totalusdValue = balances["totalusdValue"].round(2)

    @chart_balances_data = []
    @chart_payment_data = []
    balances.each do |k,v| 
      if k != "totalusdValue" && v["usdValue"] > 0
        if k != "USD"
          list_index[k] = li
          @chart_payment_data << {name: k, data:[]}
          li += 1
        end
        @chart_balances_data << [k, v["usdValue"].round(2)]
      end
    end

    db_data = FundingPayment.where("time > ?", 30.day.ago).order("time asc").pluck(:coin_name, :time, :payment, :rate).map { |coin_name, time, payment, rate| {coin_name: coin_name, time: time, payment: payment, rate: rate}}
    fundingpayments = db_data.group_by{|fp| fp[:coin_name]}.transform_values {|k| k.group_by_day(format: '%F') { |fp| fp[:time] }}

    payments ,costs = {}, {}
    a_week_ago = 7.day.ago

    data_init = {}
    (30.day.ago.to_date..Date.today).each {|date| data_init[date.strftime('%F')] = 0 }

    fundingpayments.each do |coin_name, dataset|

      chart_payment_tmp = {coin_name => data_init.clone}
      dataset.each do |day, data_arr|
        data_arr.each do |data|

          payment = 0 - data[:payment]
          rate = data[:rate]

          chart_payment_tmp[coin_name][day] += payment

          payments[coin_name] = {weekly: 0, monthly: 0} unless payments[coin_name]
          costs[coin_name] = {weekly: 0, monthly: 0} unless costs[coin_name]

          payments[coin_name][:monthly] += payment
          costs[coin_name][:monthly] += payment / rate unless rate == 0

          if day > a_week_ago
            payments[coin_name][:weekly] += payment
            costs[coin_name][:weekly] += payment / rate unless rate == 0
          end
        end
      end

      unless list_index[coin_name]
        list_index[coin_name] = list_index.size
        @chart_payment_data << {name: coin_name, data: []}
      end
      @chart_payment_data[list_index[coin_name]][:data] = chart_payment_tmp[coin_name].to_a
    end

    render locals: {totalusdValue: totalusdValue, payments: payments, costs: costs, list_index: list_index}
  end

  def show
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
    
    coin_name = params["coin_name"] ? params["coin_name"] : "BTC"
    @coin = Coin.includes(:current_fund_stat).find_by("name = ?", coin_name)

    @funding_orders = FundingOrder.includes(coin: :current_fund_stat).all.order("created_at desc")
    
    @underway_order = @funding_orders.where(:order_status => "Underway").last
    # 如果order_status有問題，要顯示出來

    @position = {"netSize" => 0, "cost" => 0}
    FtxClient.account["result"]["positions"].each do |position|
      if position["future"].split("-")[0] == @coin.name
        @position = {
          "netSize" => position["netSize"],
          "cost" => position["cost"]}
      end
    end

    @fund_stat = @coin.current_fund_stat
    rates = @coin.rates.where("time > ?", Time.now - 6.weeks).order("time asc")

    @line_chart_data = rates.map { |r| [r.time.strftime('%m/%d %H:%M'),r.rate*100]}
    @zeros = @line_chart_data.map { |t,r| [t,0] }

    balances = ftx_wallet_balance
    balances[@coin.name] = {"amount"=>0.0, "usdValue"=>0.0} unless balances[@coin.name]

    @funding_order = FundingOrder.new(
      :coin_id => @coin.id, 
      :coin_name => @coin.name,
      :original_coin_amount => balances[@coin.name]["amount"],
      :original_perp_amount => @position["netSize"]
      )

    render locals: {balances: balances}
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
  def ftx_wallet_balance
    balances = {"totalusdValue" => 0.00}

    ftx_wallet_balances_response = FtxClient.wallet_balances
    if ftx_wallet_balances_response["success"] 
      ftx_wallet_balances_response["result"].each do |result|
        balances[result["coin"]] = {"amount" => result["availableWithoutBorrow"], "usdValue" => result["usdValue"]}
        balances["totalusdValue"] += result["usdValue"]
      end
    end    
    return balances
  end

  def createorder_params
    params.require(:funding_order).permit(:coin_id,:coin_name,
                                          :original_coin_amount,:original_perp_amount,
                                          :target_coin_amount,:target_perp_amount,
                                          :acceleration,:threshold)
  end
end