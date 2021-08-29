class FtxClient
  attr_accessor :method, :auth, :subaccount, :url

  def initialize params = {}
    init = {method: "GET", url: "https://ftx.com", auth: false}

    init.merge(params).each { |key, value| send "#{key}=", value }
  end

  def self.account(subaccount)
    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("GET", "/api/account")
  end

  def self.wallet_balances(subaccount)
    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("GET", "/api/wallet/balances")
  end

  def self.positions(subaccount)
    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("GET", "/api/positions")
  end

  def self.funding_payments(subaccount, params = {})
    # start_time        number  1559881511  optional
    # end_time          number  1559881711  optional
    # future            string  BTC-PERP    optional

    params_str = ""
    unless params.empty?
      params.each {|k,v| params_str += "&#{k}=#{v}"}
      params_str[0]="?"
    end

    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("GET", "/api/funding_payments" + params_str)
  end

  def self.order_history(subaccount, params = {})
    
    params_str = ""
    unless params.empty?
      params.each {|k,v| params_str += "&#{k}=#{v}"}
      params_str[0]="?"
    end

    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("GET", "/api/orders/history" + params_str)
  end

  def self.place_order(subaccount, params = {})
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

    # params = {market: "BTC-PERP", side: "buy", price: 5000, size: 0.001, type: "limit"}

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

    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("POST", "/api/orders", {payload: payload})
  end
 
  def self.cancel_order(subaccount, order_id)
    return FtxClient.new(:auth => true, :subaccount => subaccount)._request("DELETE", "/api/orders/#{order_id}")
  end

  def self.future_stats(future_name)
    return FtxClient.new._request("GET", "/api/futures/#{future_name}/stats")
  end

  def self.funding_rates(params={})
    params_str = ""
    unless params.empty?
      params.each {|k,v| params_str += "&#{k}=#{v}"}
      params_str[0]="?"
    end

    return FtxClient.new._request("GET", "/api/funding_rates" + params_str)
  end

  def self.market_info(market)
    # BTC/USD, BTC-PERP, BTC-0626
    return FtxClient.new._request("GET", "/api/markets/#{market}")
  end

  def self.markets_info
    return FtxClient.new._request("GET", "/api/markets")
  end

  def self.orderbook(market, params = {})
    params_str = ""

    unless params.empty?
      params.each {|k,v| params_str += "&#{k}=#{v}"}
      params_str[0]="?"
    end

    return FtxClient.new._request("GET", "/api/markets/#{market}/orderbook" + params_str)
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
        Rails.application.credentials.ftx[self.subaccount.to_sym][:sec], 
        signature_payload)
      
      headers = {
        'FTX-KEY' => Rails.application.credentials.ftx[self.subaccount.to_sym][:pub],
        'FTX-SIGN' => signature,
        'FTX-TS' => ts,
        'FTX-SUBACCOUNT' => self.subaccount}
      headers['Content-Type'] = 'application/json' if payload
    end

    response_is_JSON = false
    retry_time = 0

    until response_is_JSON || retry_time >= 5
      response = RestClient::Request.execute(
        :method => http_method.to_sym, 
        :url => req_url, 
        :payload => payload,
        :headers => headers) {|response, request, result| response }
      begin
        return_data = JSON.parse(response.body)
        response_is_JSON = true
      rescue
        retry_time += 1
        puts "(attempt: #{retry_time}) FtxClient request of #{req_url} is not JSON. => " + Nokogiri::HTML.parse(response.body).title
        sleep(5)
        return_data = Nokogiri::HTML.parse(response.body).title
        response_is_JSON = false
      end
    end
    
    return return_data
  end
end
