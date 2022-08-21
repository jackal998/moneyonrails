namespace :funding do
  task update_coin_stats: :environment do
    def logger
      Logger.new("log/task_funding_update_coin_stats.log")
    end

    def calculate_raw_irr(raw_irr, rate)
      (raw_irr * (1 + rate.rate)).round(6)
    end

    init_time = Time.now
    last_48_hrs = 2.days.ago.beginning_of_hour
    last_week = 1.week.ago.beginning_of_hour

    irr = {week: 1, month: 1}
    success_rate = {two_days: 0.00, week: 0.00}

    @coins = Coin.with_perp.includes(:sorted_rates).where(sorted_rates: {time: 1.month.ago.beginning_of_hour..})

    logger.info "updating: #{@coins.size}"
    fund_stat_datas_tbu = []

    @coins.each do |coin|
      retry_count = 0
      # finding ways to websocket ftx...
      data = {"success" => false}
      until data["success"] || retry_count >= 3
        data = FtxClient.future_stats("#{coin.name}-PERP")

        unless data["success"]
          retry_count += 1
          logger.warn "ftx response #{coin.name}-PERP failed #{data} #{retry_count}/3"
          sleep(1)
        end
      end

      next if retry_count >= 3

      coin.sorted_rates.each do |rate|
        irr[:month] = calculate_raw_irr(irr[:month], rate)
        next if rate.time < last_week
        irr[:week] = calculate_raw_irr(irr[:week], rate)
        next if rate.rate < 0
        success_rate[:week] += 1
        next if rate.time < last_48_hrs
        success_rate[:two_days] += 1
      end

      fund_stat_datas_tbu << {}.tap do |h|
        h[:coin_id] = coin.id
        h[:nextFundingRate] = data["result"]["nextFundingRate"]
        h[:nextFundingTime] = data["result"]["nextFundingTime"]
        h[:openInterest] = data["result"]["openInterest"]
        h[:rate] = coin.sorted_rates.last.rate
        h[:success_rate_past_48_hrs] = (success_rate[:two_days] / 48).round(5)
        h[:success_rate_past_week] = ((success_rate[:week] / (7 * 24))).round(5)
        h[:irr_past_week] = (((irr[:week] - 1) / 7) * 365).round(3)
        h[:irr_past_month] = ((irr[:month] - 1) * 12).round(3)
      end
    end

    update_columns = %i[coin_id
      nextFundingRate
      nextFundingTime
      openInterest
      rate
      success_rate_past_48_hrs
      success_rate_past_week
      irr_past_week
      irr_past_month]

    result = CoinFundingStat.import fund_stat_datas_tbu, on_duplicate_key_update: {conflict_target: :coin_id, columns: update_columns}, batch_size: 10000

    logger.info result
    logger.info "update ok (#{Time.now - init_time}s)"
  end

  task update_payments: :environment do
    def logger
      Logger.new("log/task_funding_update_payments.log")
    end

    init_time = Time.now

    @users = User.can_funding
    coin_ids = Coin.with_perp.pluck(:name, :id).to_h
    latest_funding_payments = FundingPayment
      .group("user_id", "coin_name")
      .maximum(:time)
      .each_with_object({}) do |((user_id, coin_name), time), h|
        if h[user_id]
          h[user_id][coin_name] = time
        else
          h[user_id] = {coin_name => time}
        end
      end

    logger.info "Total users: #{@users.size}"
    funding_payment_datas_tbu = []

    @users.each do |user|
      query_start_time = [latest_funding_payments[user.id]&.values&.min, 1.day.ago.beginning_of_hour].compact.max

      pre_size, retry_count = 0, 0
      data = {"success" => false, "result" => []}

      until data["success"] && pre_size == data["result"].size || retry_count >= 3
        pre_size = data["result"].size

        data = FtxClient.funding_payments(user.funding_account, {start_time: query_start_time.to_i})

        unless data["success"]
          retry_count += 1
          logger.warn "ftx response for user: #{user.id} failed #{data} #{retry_count}/3"
          data["result"] = []
          sleep(1)
        end
      end

      last_response_data_count = data["result"].size

      if last_response_data_count.in?(1..500)
        funding_payment_datas_tbu += data["result"].map do |result|
          coin_name, _ = result["future"].split("-")
          latest_payment_time = latest_funding_payments[user.id]&.[](coin_name)
          next if latest_payment_time && latest_payment_time >= result["time"].to_time
          FundingPayment.new(
            coin_id: coin_ids[coin_name],
            user_id: user.id,
            coin_name: coin_name,
            created_at: Time.now,
            updated_at: Time.now,
            **result.slice("payment", "rate", "time")
          )
        end
      else
        logger.error "ftx response response_size = #{last_response_data_count}, please check rake logic."
      end
    end

    FundingPayment.import funding_payment_datas_tbu.compact, validate: true, validate_uniqueness: true, batch_size: 10000

    logger.info "update ok (#{Time.now - init_time}s)"
  end

  task update_stats: :environment do
    def logger
      Logger.new("log/task_funding_update_stats.log")
    end

    def irr_calculator(data)
      {}.tap do |h|
        FundingStat::DISPLAY_PERIODS.each do |d|
          sym_payment = "last_#{d}_day_payments".to_sym
          sym_irr = "last_#{d}_day_irr".to_sym

          h[sym_payment] = - data[d][:payment].round(2)
          h[sym_irr] = - ((data[d][:payment] / data[d][:open_size]) * 24 * 365 * 100).round(2) unless data[d][:open_size] == 0
        end
      end
    end

    init_time = Time.now
    user_fundingpayments = FundingPayment
      .where(time: 1.year.ago..)
      .order("time asc")
      .group_by(&:user_id)
      .transform_values do |fundingpayment|
        fundingpayment
          .group_by(&:coin_name)
          .transform_values do |fundingpayment|
            fundingpayment.group_by_day(format: "%F") { |fundingpayment| fundingpayment[:time] }
          end
      end

    logger.info "Total users: #{user_fundingpayments.size}"

    coin_ids = Coin.pluck(:name, :id).to_h

    funding_stats_tbu = []
    raw_data_hash = {}

    user_fundingpayments.each do |user_id, coin_name_fundingpayments|
      raw_data_hash[user_id] = {}
      raw_data_hash[user_id][:total_of_coins] ||= {}

      coin_name_fundingpayments.each do |coin_name, date_fundingpayments|
        raw_data_hash[user_id][coin_name] = {}

        date_fundingpayments.each do |day, fundingpayments|
          date_fundingpayment_info = fundingpayments.inject({payment: 0, open_size: 0}) do |result, data|
            {}.tap do |h|
              h[:payment] = result[:payment] + data.payment
              h[:open_size] = result[:open_size] + (data.rate&.nonzero? ? data.payment / data.rate : 0)
            end
          end

          FundingStat::DISPLAY_PERIODS.each do |d|
            [coin_name, :total_of_coins].each do |name|
              raw_data_hash[user_id][name][d] ||= {payment: 0, open_size: 0}

              if day >= d.day.ago
                raw_data_hash[user_id][name][d].tap do |h|
                  h[:payment] += date_fundingpayment_info[:payment]
                  h[:open_size] += date_fundingpayment_info[:open_size]
                end
              end
            end
          end
        end

        funding_stats_tbu << FundingStat.new(
          user_id: user_id,
          coin_id: coin_ids[coin_name],
          coin_name: coin_name,
          **irr_calculator(raw_data_hash[user_id][coin_name])
        )
      end

      funding_stats_tbu << FundingStat.new(
        user_id: user_id,
        coin_name: :total_of_coins,
        **irr_calculator(raw_data_hash[user_id][:total_of_coins])
      )
    end

    update_columns = (FundingStat.column_names - %w[id created_at]).map(&:to_sym)
    result = FundingStat.import funding_stats_tbu, on_duplicate_key_update: {conflict_target: [:user_id, :coin_name], columns: update_columns}, batch_size: 10000

    logger.info result
    logger.info "update ok (#{Time.now - init_time}s)"
  end
end
