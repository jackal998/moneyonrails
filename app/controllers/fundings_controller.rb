class FundingsController < ApplicationController
  def index

    helpers.update_market_infos if Time.now - CurrentFundStat.last.updated_at > 15
    @coins = Coin.includes(:current_fund_stat).where(current_fund_stat: {market_type: "normal"}).order("current_fund_stat.irr_past_month desc")
  end

  def ftx_with_auth
    ts = DateTime.now.strftime('%Q')
    ftx_api = "https://ftx.com"
    api_endpoint = "/api/account"
    req_url = ftx_api + api_endpoint
    rest_method = "GET"

    key = ""
    signature_payload = ts + rest_method + api_endpoint
    signature = OpenSSL::HMAC.hexdigest("SHA256", key, signature_payload)

    response = RestClient::Request.execute(
      :method => rest_method.to_sym, 
      :url => req_url, 
      :headers => {
        'FTX-KEY' => "",
        'FTX-SIGN' => signature,
        'FTX-TS' => ts})
      # :payload => post_params, 
      # :timeout => 9000000, 
    data = JSON.parse(response.body)
  end
end
