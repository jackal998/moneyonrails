namespace :market do

  task :update_infos => :environment do

    def coin_data_equal?(coin, tmp_attr)
      case
      when coin.minProvideSize != [tmp_attr[:perpminProvideSize].to_f, tmp_attr[:spotminProvideSize].to_f].max then return false
      when coin.have_perp != tmp_attr[:have_perp] then return false
      when coin.perppriceIncrement != tmp_attr[:perppriceIncrement] then return false
      when coin.perpsizeIncrement != tmp_attr[:perpsizeIncrement] then return false
      when coin.spotpriceIncrement != tmp_attr[:spotpriceIncrement] then return false
      when coin.spotsizeIncrement != tmp_attr[:spotsizeIncrement] then return false
      end
      true
    end

    def logger
      Logger.new('log/task_market_update_infos.log')
    end

    def coin_attr(coin, data)
      # attributes returns string type key
      coin.attributes.merge(
        "spotpriceIncrement" => data[:spotpriceIncrement],
        "spotsizeIncrement" => data[:spotsizeIncrement],
        "perppriceIncrement" => data[:perppriceIncrement],
        "perpsizeIncrement" => data[:perpsizeIncrement],
        "minProvideSize" => [data[:perpminProvideSize].to_f, data[:spotminProvideSize].to_f].max,
        "have_perp" => data[:have_perp],
        "updated_at" => Time.now)
    end

    def coin_attr_to_output(coin_attr)
      coin_attr.select {|k,v| {k => v} if ["id", "name", "minProvideSize", "have_perp", "spotpriceIncrement", "spotsizeIncrement", "perppriceIncrement", "perpsizeIncrement"].include?(k)}.to_s
    end

    def fund_stat_attr(fund_stat, data)
      fund_stat.attributes.merge(
        "market_type" => data[:market_type],
        "perp_price_usd" => data[:perp_price_usd],
        "perp_bid_usd" => data[:perp_bid_usd],
        "perp_ask_usd" => data[:perp_ask_usd],
        "perp_volume" => data[:perp_volume],
        "spot_price_usd" => data[:spot_price_usd],
        "spot_bid_usd" => data[:spot_bid_usd],
        "spot_ask_usd" => data[:spot_ask_usd],
        "spot_volume" => data[:spot_volume],
        "perp_over_spot" => data[:perp_over_spot],
        "spot_over_perp" => data[:spot_over_perp],
        "updated_at" => Time.now)
    end

    def tmp_attr(type, result)
      case type
      when "perp"
        { :perp_price_usd => result["price"],
          :perp_bid_usd => result["bid"],
          :perp_ask_usd => result["ask"],
          :perp_volume => result["volumeUsd24h"],
          :perppriceIncrement => result["priceIncrement"],
          :perpsizeIncrement => result["sizeIncrement"],
          :perpminProvideSize => result["minProvideSize"]}
      when "spot"
        { :spot_price_usd => result["price"],
          :spot_bid_usd => result["bid"],
          :spot_ask_usd => result["ask"],
          :spot_volume => result["volumeUsd24h"],
          :spotpriceIncrement => result["priceIncrement"],
          :spotsizeIncrement => result["sizeIncrement"],
          :spotminProvideSize => result["minProvideSize"]}
      end
    end
    
    init_time = Time.now
    
    data = {"result" => []}
    responce_size = 0
    while responce_size != data["result"].size || responce_size == 0
      responce_size = data["result"].size
      data = FtxClient.markets_info
      if responce_size != data["result"].size && responce_size != 0
        logger.warn "ftx response size mismatch, prev: #{responce_size} <> last: #{data["result"].size}"
        sleep(2)
      end
      sleep(1)
    end

    tmp = {}
    result_spot_counts, result_perp_counts, result_funding_counts = 0, 0, 0

    data["result"].each do |result|
      case
      when result["type"] == "spot" && result["quoteCurrency"] == "USD"
        data_type = "spot"
        coin_name = result["baseCurrency"]
        result_spot_counts += 1
      when result["type"] == "future" && result["futureType"] == "perpetual"
        data_type = "perp"
        coin_name = result["underlying"]
        result_perp_counts += 1
      else next
      end

      tmp[coin_name] = {:market_type => "", :have_perp => false} unless tmp[coin_name]
      tmp[coin_name].merge!(tmp_attr(data_type, result))

      case data_type
      when "perp"
        tmp[coin_name][:have_perp] = true
        tmp[coin_name][:market_type] += "f"
      when "spot"
        tmp[coin_name][:market_type] += "s"
      end
      
      if ["fs", "sf"].include?(tmp[coin_name][:market_type])
        result_funding_counts += 1
        # 以市價成交計算，空PERP看的是買單價格(bid)，買現貨看賣單價格(ask)
        tmp[coin_name].merge!({
          :market_type => "normal",
          :perp_over_spot => tmp[coin_name][:perp_bid_usd] / tmp[coin_name][:spot_ask_usd],
          :spot_over_perp => tmp[coin_name][:spot_bid_usd] / tmp[coin_name][:perp_ask_usd]})
      end
    end

    logger.info "result_spot_counts: #{result_spot_counts}, result_perp_counts: #{result_perp_counts}, result_funding_counts: #{result_funding_counts}"

    current_coin_counts, matched_coin_counts, unlisted_coin_counts = 0, 0, 0
    coin_datas_tbu, fund_stat_datas_tbu = [], []
    last_coin_id = 0

    @coins = Coin.includes(:current_fund_stat).order("id ASC").all
    @coins.each do |coin|
      current_coin_counts += 1
      if tmp[coin.name]
        matched_coin_counts += 1
        fund_stat_datas_tbu << fund_stat_attr(coin.current_fund_stat , tmp[coin.name])
        coin_datas_tbu << coin_attr(coin , tmp[coin.name]) unless coin_data_equal?(coin, tmp[coin.name])
        tmp.except!(coin.name)
      else
        unlisted_coin_counts += 1
        # todo auto hide
        logger.error "ftx response coin: #{coin.name} missing."
      end
    end

    logger.info "current_coin_counts: #{current_coin_counts}, matched_coin_counts: #{matched_coin_counts}, unlisted_coin_counts: #{unlisted_coin_counts}"
    
    if !coin_datas_tbu.empty?
      logger.info "update coins attr: #{coin_datas_tbu.size}"
      coin_datas_tbu.each {|coin_data| logger.info coin_attr_to_output(coin_data)}
    end

    new_coin_counts = tmp.size
    last_coin_id = @coins.empty? ? 0 : @coins.last.id
    last_fund_stat_id = @coins.empty? ? 0 : @coins.last.current_fund_stat.id
    
    tmp.each do |coin_name, result|
      last_coin_id += 1
      last_fund_stat_id += 1
      
      coin_datas_tbu << coin_attr(Coin.new(:id => last_coin_id, :name => coin_name, :created_at => Time.now), result)
      fund_stat_datas_tbu << fund_stat_attr(CurrentFundStat.new(:id => last_fund_stat_id, :coin_id => last_coin_id, :created_at => Time.now), result)
    end

    Coin.upsert_all(coin_datas_tbu) unless coin_datas_tbu.empty? 
    CurrentFundStat.upsert_all(fund_stat_datas_tbu) unless fund_stat_datas_tbu.empty? 

    logger.info "new coin counts: #{tmp.size}, #{tmp.keys}" unless tmp.empty?

    logger.info "========= Done ==========  #{(Time.now - init_time).round(3)}s"
  end
end