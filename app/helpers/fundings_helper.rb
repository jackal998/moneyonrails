module FundingsHelper
  def get_funding_infos(coins)

    infos = {}
    coins.each do |coin|

# check local data first

      # if coin.have_perp 
      # finding ways to websocket ftx...
      if false
        ftxgetfuturestatsurl = "https://ftx.com/api/futures/#{coin.name}-PERP/stats"   
        
        response = RestClient.get ftxgetfuturestatsurl
        data = JSON.parse(response.body)

        data["result"]["nextFundingRate"] = (data["result"]["nextFundingRate"] * 100).round(4).to_s + "%"

        infos["#{coin.name}"] = data["result"]
      end   
    end
    return infos
  end


  def update_market_infos
    ftxmarketsurl = "https://ftx.com/api/markets"   
    
    response = RestClient.get ftxmarketsurl 
    data = JSON.parse(response.body)

    tmp = {}

    data["result"].each do |result|
      next unless result["quoteCurrency"] == "USD" || result["name"].include?("PERP")

      coin_name = result["underlying"] || result["baseCurrency"]

      c = Coin.create(:name => coin_name, :have_perp => false) unless c = Coin.find_by(:name => coin_name)

      unless tmp[coin_name]
        tmp[coin_name] = c.current_fund_stat ? c.current_fund_stat : CurrentFundStat.new(:coin => c,:market_type => "")
      end

      case result["type"]
      when "future"
        tmp[coin_name].assign_attributes(
          :perp_price_usd => result["price"],
          :perp_bid_usd => result["bid"],
          :perp_ask_usd => result["ask"],
          :perp_volume => result["volumeUsd24h"])
        
        tmp[coin_name]["market_type"] = tmp[coin_name]["market_type"] ? tmp[coin_name]["market_type"] += "f" : "f"

        unless c.minProvideSize
          c.update(
            :priceIncrement => result["priceIncrement"],
            :sizeIncrement => result["sizeIncrement"],
            :minProvideSize => result["minProvideSize"])
        end  
        
        c.update_attribute(:have_perp , true) unless c.have_perp
      when "spot"
        tmp[coin_name].assign_attributes(
          :spot_price_usd => result["price"],
          :spot_bid_usd => result["bid"],
          :spot_ask_usd => result["ask"],
          :spot_volume => result["volumeUsd24h"])

        tmp[coin_name]["market_type"] = tmp[coin_name]["market_type"] ? tmp[coin_name]["market_type"] += "s" : "s"
      end
      
      if tmp[coin_name].data_calc_ready?
        # 以市價成交計算，空PERP看的是買單價格(bid)，買現貨看賣單價格(ask)
        tmp[coin_name].assign_attributes(
          :market_type => "normal",
          :perp_over_spot => tmp[coin_name]["perp_bid_usd"] / tmp[coin_name]["spot_ask_usd"],
          :spot_over_perp => tmp[coin_name]["spot_bid_usd"] / tmp[coin_name]["perp_ask_usd"])
        tmp[coin_name].save
      end
    end
    puts "update_market_infos ok with #{tmp.count} datas from FTX."
  end
end