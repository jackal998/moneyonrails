module FundingsHelper
  def get_funding_index_infos(coins)

    infos = {}
    coins.each do |coin|

# check local data first

      if coin.have_perp
        ftxgetfuturestatsurl = "https://ftx.com/api/futures/#{coin.name}-PERP/stats"   
        
        response = RestClient.get ftxgetfuturestatsurl
        data = JSON.parse(response.body)

        data["result"]["nextFundingRate"] = (data["result"]["nextFundingRate"] * 100).round(4).to_s + "%"

        infos["#{coin.name}"] = data["result"]
      end   
    end
    return infos
  end
end
