class OrderExecutorJob < ApplicationJob
  queue_as :default

  def logger
    Logger.new("log/order_executor_job.log")
  end

  def initialize_params(funding_order_id)
    @funding_order = FundingOrder.find(funding_order_id)
    return false unless @funding_order.order_status == "Underway"

    @coin = Coin.find(@funding_order.coin_id)
    @funding_account = @funding_order.user.funding_account
    @_every_timer = {}
  end

  def perform(funding_order_id)
    return unless initialize_params(funding_order_id)
    logger.info(funding_order_id) { "starting..." }

    spot_name = @coin.name
    spot_market_name = "#{@coin.name}/USD"
    perp_market_name = "#{@coin.name}-PERP"

    set_order_config(spot_name, perp_market_name)
    order_status = @order_config[:order_status]

    while order_status == "Underway"
      order_status = Rails.cache.read("funding_order:#{@funding_order.id}:order_status") || order_status
      break unless order_status == "Underway"

      # BTC/USD, BTC-PERP, BTC-0626
      market_infos = get_market_infos({spot: spot_market_name, perp: perp_market_name})
      current_ratio = get_current_ratio(market_infos) if market_infos.values.pluck("success").all?(true)

      if every_second?(29)
        logger.info(@funding_order.id) { "#{spot_name}, Current ratio: #{current_ratio}, Threshold: #{@funding_order.threshold}, Direction: #{@order_config[:direction]}" }
      end

      next sleep(1) if current_ratio < @funding_order.threshold
      order_result = place_funding_orders(get_payload(spot_market_name, perp_market_name))
      order_result.each do |type, result|
        logger.info(@funding_order.id) { "#{type}_order_result: #{order_result[type]}" } if order_result[type]
      end

      # 有下單，但是API回傳還沒有更新的時候，會造成連續下單，在特別的條件會下超過指定部位
      sleep(0.8)
      pre_config = @order_config.dup
      set_order_config(spot_name, perp_market_name)
      # 下單前後甚麼事情都沒發生，不Loop直接退出
      break order_status = "Nothing Happened" if pre_config == @order_config
      order_status = @order_config[:order_status]
    end

    case order_status
    when "Close"
      logger.info(@funding_order.id) { "complete." }
      @funding_order[:order_status] = "Close"
    when "Abort"
      update_order_description_and_generate_system_order("Manual abort.", spot_name, perp_market_name)
    when "Nothing Happened"
      # 下單前後甚麼事情都沒發生，只有可能出現在加倉時買不了幣(因為合約市價下單不太可能沒變化)
      # 所以先平掉多餘的合約
      payload_perp = {market: perp_market_name, side: "buy", price: nil, type: "market", size: order_sizer("spot")}
      FtxClient.place_order(@funding_account, payload_perp)
      update_order_description_and_generate_system_order("Order(s) were not executed.", spot_name, perp_market_name)
    else
      update_order_description_and_generate_system_order(order_status, spot_name, perp_market_name)
    end

    Rails.cache.delete("funding_order:#{@funding_order.id}:order_status")
    @funding_order.save!
  end

  def refresh_funding_order
    @funding_order = FundingOrder.uncached { FundingOrder.find(@funding_order.id) }
  end

  def every_second?(number)
    unix_time = Time.now.to_i
    return false if @_every_timer[number] == unix_time
    @_every_timer[number] = unix_time
    unix_time % number == 0
  end

  def order_sizer(type)
    size = [@coin.spotsizeIncrement, @coin.perpsizeIncrement].max
    [@order_config["#{type}_steps".to_sym].abs, @funding_order.acceleration].min * size
  end

  def set_order_config(spot_name, perp_market_name)
    account_data = get_account_amount(spot_name, perp_market_name)
    size = [@coin.spotsizeIncrement, @coin.perpsizeIncrement].max

    @order_config = {}.tap do |h|
      h[:order_status] = @funding_order.order_status
      h[:spot_bias] = @funding_order.target_spot_amount - account_data[spot_name]
      h[:spot_steps] = (h[:spot_bias] / size).round(0)

      h[:perp_bias] = @funding_order.target_perp_amount - account_data[perp_market_name]
      h[:perp_steps] = (h[:perp_bias] / size).round(0)
      h[:direction] = h[:spot_steps] > h[:perp_steps] ? "more" : "less"

      step_bias = h[:spot_steps] + h[:perp_steps]

      if step_bias.nonzero?
        if h[:direction] == "more" && step_bias > 0 || h[:direction] == "less" && step_bias < 0
          h[:spot_steps] = step_bias
          h[:perp_steps] = 0
        else
          h[:spot_steps] = 0
          h[:perp_steps] = step_bias
        end
      end

      h[:order_status] = "Close" if h[:spot_steps].zero? && h[:perp_steps].zero?

      logger.info(@funding_order.id) do
        "
        account_data: #{account_data.to_json}
        direction: #{h[:direction]}
        spot_bias: #{h[:spot_bias]} => spot_steps: #{h[:spot_steps]}
        perp_bias: #{h[:perp_bias]} => perp_steps: #{h[:perp_steps]}"
      end
    end
  end

  def get_market_infos(params)
    params.each_with_object({}) do |(key, market_name), h|
      h[key] = FtxClient.market_info(market_name)
    end
  end

  def get_account_amount(spot_name, perp_market_name)
    wallet_balances_data = FtxClient.wallet_balances(@funding_account)
    positions_data = FtxClient.positions(@funding_account)

    return {} unless positions_data["success"] && wallet_balances_data["success"]

    {}.tap do |h|
      h[spot_name] = wallet_balances_data["result"].detect { |result| result["coin"] == spot_name }&.dig("total") || 0
      h[perp_market_name] = positions_data["result"].detect { |result| result["future"] == perp_market_name }&.dig("netSize") || 0
    end
  end

  def get_current_ratio(market_infos)
    spot_data = market_infos[:spot]
    perp_data = market_infos[:perp]

    case @order_config[:direction]
    when "more"
      (perp_data["result"]["bid"] / spot_data["result"]["ask"] - 1) * 100
    when "less"
      (spot_data["result"]["bid"] / perp_data["result"]["ask"] - 1) * 100
    end
  end

  def get_payload(spot_market_name, perp_market_name)
    payload = {market: nil, side: nil, price: nil, type: "market", size: nil}

    {
      spot: payload.merge({market: spot_market_name, size: order_sizer("spot")}),
      perp: payload.merge({market: perp_market_name, size: order_sizer("perp")})
    }
  end

  def place_funding_orders(payloads)
    order_flow = case @order_config[:direction]
    when "more"
      # 先買現貨，再空永續
      [:spot, :perp]
    when "less"
      # 先平永續，再賣現貨
      [:perp, :spot]
    end

    order_flow.zip(["buy", "sell"]).each_with_object({}) do |(type, side), h|
      next if payloads[type][:size].zero?
      # no DDoS
      sleep(0.2) if h.present?
      h[type] = FtxClient.place_order(@funding_account, payloads[type].merge(side: side))
    end
  end

  def update_order_description_and_generate_system_order(error_msg, spot_name, perp_market_name)
    @funding_order[:description] = "System Close triggered: #{error_msg}"
    @funding_order[:order_status] = "Abort"
    logger.warn(@funding_order.id) { error_msg }
    create_system_order(error_msg, spot_name, perp_market_name)
  end

  def create_system_order(error_msg, spot_name, perp_market_name)
    account_data = get_account_amount(spot_name, perp_market_name)

    system_order = @funding_order.dup.tap do |order|
      order[:target_spot_amount] = account_data[spot_name]
      order[:target_perp_amount] = account_data[perp_market_name]
      order[:order_status] = "Close"
      order[:system] = true
      order[:description] = error_msg
    end
    system_order.save!
  end
end
