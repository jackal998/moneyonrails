class FtxClient
  attr_accessor :method, :auth, :subaccount, :url

  def initialize params = {}
    init = {method: "GET", url: "https://ftx.com/api", auth: false}

    init.merge(params).each { |key, value| send "#{key}=", value }
  end

  def self.account(subaccount)
    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/account")
  end

  def self.wallet_balances(subaccount)
    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/wallet/balances")
  end

  def self.positions(subaccount)
    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/positions")
  end

  def self.funding_payments(subaccount, params = {})
    # start_time        number  1559881511  optional
    # end_time          number  1559881711  optional
    # future            string  BTC-PERP    optional
    params_str = params_to_s(params)

    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/funding_payments" + params_str)
  end

  def self.orders(subaccount, order_id)
    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/orders/#{order_id}")
  end

  def self.open_orders(subaccount, params = {})
    params_str = params_to_s(params)

    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/orders" + params_str)
  end

  def self.order_history(subaccount, params = {})
    params_str = params_to_s(params)

    FtxClient.new(auth: true, subaccount: subaccount)._request("GET", "/orders/history" + params_str)
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

    [:market, :side, :size, :type].each { |key| return "params :#{key} missing, please check." unless params[key] }

    case params[:type]
    when "market" then return "Markettype is 'market', but given price #{params[:price]} is not nil, please check." if params[:price]
    when "limit" then return "Market type is 'limit', but price is nil, please check." unless params[:price]
    end

    payload = params.to_json

    FtxClient.new(auth: true, subaccount: subaccount)._request("POST", "/orders", {payload: payload})
  end

  def self.cancel_order(subaccount, order_id)
    FtxClient.new(auth: true, subaccount: subaccount)._request("DELETE", "/orders/#{order_id}")
  end

  def self.future_stats(future_name)
    FtxClient.new._request("GET", "/futures/#{future_name}/stats")
  end

  def self.funding_rates(params = {})
    params_str = params_to_s(params)

    FtxClient.new._request("GET", "/funding_rates" + params_str)
  end

  def self.market_info(market)
    # BTC/USD, BTC-PERP, BTC-0626
    FtxClient.new._request("GET", "/markets/#{market}")
  end

  def self.markets_info
    FtxClient.new._request("GET", "/markets")
  end

  def self.orderbook(market, params = {})
    params_str = params_to_s(params)

    FtxClient.new._request("GET", "/markets/#{market}/orderbook" + params_str)
  end

  def self.withdrawals_for_validation(subaccount, params = {})
    # NOT A REAL FUNCTION, used in api validation
    FtxClient.new(auth: true, subaccount: subaccount)._request("POST", "/wallet/withdrawals", {payload: {}.to_json})
  end

  def _request(http_method, path, params = {})
    req_url = url + path
    payload = params[:payload] if params[:payload]

    if auth
      ts = DateTime.now.strftime("%Q")

      signature_payload = ts + http_method + "/api" + path
      signature_payload += payload if payload
      signature = OpenSSL::HMAC.hexdigest(
        "SHA256",
        subaccount.crypt.decrypt_and_verify(subaccount[:encrypted_secret_key]),
        signature_payload
      )
      headers = {
        "FTX-KEY" => subaccount.crypt.decrypt_and_verify(subaccount[:encrypted_public_key]),
        "FTX-SIGN" => signature,
        "FTX-TS" => ts,
        "FTX-SUBACCOUNT" => subaccount.name
      }
      headers["Content-Type"] = "application/json" if payload
    end

    response_is_JSON = false
    retry_time = 0

    until response_is_JSON || retry_time >= 5
      response = RestClient::Request.execute(
        method: http_method.to_sym,
        url: req_url,
        payload: payload,
        headers: headers
      ) { |response, request, result| response }
      begin
        return_data = JSON.parse(response.body)
        response_is_JSON = true
      rescue
        retry_time += 1
        return_data = Nokogiri::HTML.parse(response.body)
        puts "(attempt: #{retry_time}) FtxClient return_data of #{req_url} is not JSON. => " + return_data.title
        sleep(2)
        puts return_data if retry_time >= 5
        response_is_JSON = false
      end
    end

    return_data
  end

  private

  def self.params_to_s(params = {}, params_str = "")
    params&.each { |k, v| params_str += params_str.empty? ? "?#{k}=#{v}" : "&#{k}=#{v}" }
    params_str
  end
end
