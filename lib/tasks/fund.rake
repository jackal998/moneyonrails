namespace :funding do
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
