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

  def self.funding_payments(params = {})
    # start_time        number  1559881511  optional
    # end_time          number  1559881711  optional
    # future            string  BTC-PERP    optional

    params_str = ""
    unless params.empty?
      params.each {|k,v| params_str += "&#{k}=#{v}"}
      params_str[0]="?"
    end

    return FtxClient.new(:auth => true)._request("GET", "/api/funding_payments" + params_str)
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

    params = {market: "BTC-PERP",side: "buy",price: 5000,size: 0.001,type: "limit"}

    [:market, :side, :size, :type].each do |key|
      return "params: :#{key} is nil, please check." unless params[key]
    end

    case params[:type]
      when "market"
        return 'Markettype is "market", but given price #{params[:price]} is not nil, please check.' if params[:price]

      when "limit"
        return 'Market type is "limit", but price is nil, please check.' unless params[:price]
    end

    payload = params.to_json

    return FtxClient.new(:auth => true)._request("POST", "/api/orders", {payload: payload})
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

    payload = params[:payload] if params[:payload]

    if self.auth
      ts = DateTime.now.strftime('%Q')

      signature_payload = ts + http_method + path
      signature_payload += payload if payload

      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.credentials.dig(:ftx_moneyonrails_sec), 
        signature_payload)

      headers = {
        'FTX-KEY' => Rails.application.credentials.dig(:ftx_moneyonrails_pub),
        'FTX-SIGN' => signature,
        'FTX-TS' => ts,
        'FTX-SUBACCOUNT' => "MoneyOnRails"}
      headers['Content-Type'] = 'application/json' if payload
    end

    response = RestClient::Request.execute(
      :method => http_method.to_sym, 
      :url => req_url, 
      :payload => payload,
      :headers => headers) {|response, request, result| response }

    return JSON.parse(response.body)
  end
end
