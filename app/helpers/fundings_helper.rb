module FundingsHelper
require 'ftx_client'

  def decimals(a)
    num = 0
    while(a != a.to_i)
        num += 1
        a *= 10
    end
    num   
  end

  def update_market_infos
    init_time = Time.now
    
    data = FtxClient.markets_info

    tmp = {}
    data_all = 0
    data_normal = 0
    cs = 0
    c_added = 0

    data["result"].each do |result|
      next unless result["quoteCurrency"] == "USD" || result["name"].include?("PERP")
      data_all += 1

      coin_name = result["underlying"] || result["baseCurrency"]

      tmp[coin_name] = {:market_type => "", :have_perp => false} unless tmp[coin_name]
      case result["type"]

      when "future"
        tmp[coin_name].merge!({
          :perp_price_usd => result["price"],
          :perp_bid_usd => result["bid"],
          :perp_ask_usd => result["ask"],
          :perp_volume => result["volumeUsd24h"],
          :perppriceIncrement => result["priceIncrement"],
          :perpsizeIncrement => result["sizeIncrement"],
          :minProvideSize => result["minProvideSize"],
          :have_perp => true})
        tmp[coin_name][:market_type] += "f"
        
      when "spot"
        tmp[coin_name].merge!({
          :spot_price_usd => result["price"],
          :spot_bid_usd => result["bid"],
          :spot_ask_usd => result["ask"],
          :spot_volume => result["volumeUsd24h"],
          :spotpriceIncrement => result["priceIncrement"],
          :spotsizeIncrement => result["sizeIncrement"]})
        tmp[coin_name][:market_type] += "s"
      end
      
      if tmp[coin_name][:market_type] == "fs" || tmp[coin_name][:market_type] == "sf"
        data_normal += 1
        # 以市價成交計算，空PERP看的是買單價格(bid)，買現貨看賣單價格(ask)
        tmp[coin_name].merge!({
          :market_type => "normal",
          :perp_over_spot => tmp[coin_name][:perp_bid_usd] / tmp[coin_name][:spot_ask_usd],
          :spot_over_perp => tmp[coin_name][:spot_bid_usd] / tmp[coin_name][:perp_ask_usd]})
      end
    end

    coin_datas_tbu = []
    fund_stat_datas_tbu = []

    Coin.includes(:current_fund_stat).each do |coin|
      cs += 1
      next unless tmp[coin.name]

      append_coin_data(coin , tmp[coin.name], coin_datas_tbu)
      CurrentFundStat.create(:coin => coin) unless coin.current_fund_stat
      append_fund_stat_data(coin.current_fund_stat , tmp[coin.name], fund_stat_datas_tbu)

      tmp.except!(coin.name)
    end

    tmp.each do |k,v|
      # k == coin_name
      coin = Coin.create(:name => "#{k}")
      append_coin_data(coin ,v , coin_datas_tbu)

      append_fund_stat_data(CurrentFundStat.create(:coin => coin) , v, fund_stat_datas_tbu)
      c_added += 1
    end

    Coin.upsert_all(coin_datas_tbu)
    CurrentFundStat.upsert_all(fund_stat_datas_tbu)

    puts "update_market_infos #{data_all - data_normal}/#{cs}(+#{c_added}) coins market data from FTX."
    puts Time.now - init_time
  end

  private
  def append_coin_data(coin, data, data_arr)
    coin.assign_attributes(
      :spotpriceIncrement => data[:spotpriceIncrement],
      :spotsizeIncrement => data[:spotsizeIncrement],
      :perppriceIncrement => data[:perppriceIncrement],
      :perpsizeIncrement => data[:perpsizeIncrement],
      :minProvideSize => data[:minProvideSize],
      :have_perp => data[:have_perp],
      :updated_at => Time.now)
      
    data_arr << coin.attributes
  end

  def append_fund_stat_data(fund_stat, data, data_arr)
    fund_stat.assign_attributes(
      :market_type => data[:market_type],
      :perp_price_usd => data[:perp_price_usd],
      :perp_bid_usd => data[:perp_bid_usd],
      :perp_ask_usd => data[:perp_ask_usd],
      :perp_volume => data[:perp_volume],
      :spot_price_usd => data[:spot_price_usd],
      :spot_bid_usd => data[:spot_bid_usd],
      :spot_ask_usd => data[:spot_ask_usd],
      :spot_volume => data[:spot_volume],
      :perp_over_spot => data[:perp_over_spot],
      :spot_over_perp => data[:spot_over_perp],
      :updated_at => Time.now)
    data_arr << fund_stat.attributes
  end
end