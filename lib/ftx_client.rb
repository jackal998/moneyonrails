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


  def self.place_order(params = {})
    # market            string  XRP-PERP    e.g. "BTC/USD" for spot, "XRP-PERP" for futures
    # side              string  sell        "buy" or "sell"
    # price             number  0.306525    Send null for market orders.
    # type              string  limit       "limit" or "market"
    # size              number  31431.0 
    # reduceOnly        boolean false       optional; default is false
    # ioc               boolean false       optional; default is false
    # postOnly          boolean false       optional; default is false
    # clientId          string  null        optional; client order id
    # rejectOnPriceBand boolean false       optional; if the order should be rejected if its price would instead be adjusted due to price bands
    
    # if you order a size smaller then the "minProvideSize", 
    # the order is automatically turned into a IOC order. You can find more info here

    params = {
      market: "BTC-PERP",
      side: "buy",
      price: 5000,
      size: 0.001,
      type: "limit"}

    payload = "{" + JSON.generate(params, {indent: ' ', space: ' ', allow_nan: false})[2..1000]

    ts = DateTime.now.strftime('%Q')
    signature_payload = ts.to_s + 'POST/api/orders' + payload

    req_url = "https://ftx.com/api/orders"

    signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      "", 
      signature_payload)

    headers = {
      'FTX-KEY' => "",
      'FTX-SIGN' => signature,
      'FTX-TS' => ts,
      'FTX-SUBACCOUNT' => "MoneyOnRails",
      'Content-Type' => 'application/json'}

    response = RestClient::Request.execute(
      :method => "POST".to_sym, 
      :url => req_url, 
      :payload => payload,
      :headers => headers)

    # need a way handling 400
    return JSON.parse(response.body)
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
      signature_payload += params["payload"] if params["payload"]

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
