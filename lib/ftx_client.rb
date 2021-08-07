class FtxClient
  attr_accessor :method, :auth, :api_key, :api_secret, :subaccount_name, :url, :end_point, :headers, :payload

  def initialize params = {}
    init = {method: "GET", url: "https://ftx.com", auth: false}

    init.each { |key, value| send "#{key}=", value.to_s }
    params.each { |key, value| send "#{key}=", value.to_s }
  end

  def self.account
    return FtxClient.new(:auth => true)._request("GET", "/api/account")
  end

  def self.wallet_balances
    return FtxClient.new(:auth => true)._request("GET", "/api/wallet/balances")
  end

  def self.positions
    return FtxClient.new(:auth => true)._request("GET", "/api/positions")
  end

  def self.market_info(market)
    # BTC/USD, BTC-PERP, BTC-0626
    return FtxClient.new._request("GET", "/api/markets/#{market}")
  end

  def self.markets_info
    return FtxClient.new._request("GET", "/api/markets")
  end
  
  def _request(http_method, path, params = {})

    req_url = self.url + path

    if self.auth
      ts = DateTime.now.strftime('%Q')

      signature_payload = ts + http_method + path
      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.credentials.dig(:ftx_moneyonrails_sec), 
        signature_payload)

      headers = {
        'FTX-KEY' => Rails.application.credentials.dig(:ftx_moneyonrails_pub),
        'FTX-SIGN' => signature,
        'FTX-TS' => ts,
        'FTX-SUBACCOUNT' => "MoneyOnRails"}
    end

    response = RestClient::Request.execute(
      :method => http_method.to_sym, 
      :url => req_url, 
      :headers => headers)
      # 'Quant-Funding'
      # :payload => post_params, 
      # :timeout => 9000000, 
    return JSON.parse(response.body)
  end
end
