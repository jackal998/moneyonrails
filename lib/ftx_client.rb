class FtxClient
  attr_accessor :auth, :api_key, :api_secret, :subaccount_name, :url, :end_point, :headers, :payload

  def initialize params = {url: "https://ftx.com", auth: false}
    params.each { |key, value| send "#{key}=", value.to_s }
  end

  def get_account_info params = {}
    # Requires authentication.
    self.auth = true
    return _get("/api/account", params)
  end

  def get_funding_rates params = {}
    return _get("/api/funding_rates", params)
  end

private
  def _get(path, params)
    return _request("GET", path, params)
  end

  def _request(http_method, path, params)

    req_url = self.url + path

    if self.auth
      keys = ""
      keyp = ""
      ts = DateTime.now.strftime('%Q')
      signature_payload = ts + http_method + path
      signature = OpenSSL::HMAC.hexdigest("SHA256", keys, signature_payload)
      headers = {
        'FTX-KEY' => keyp,
        'FTX-SIGN' => signature,
        'FTX-TS' => ts,
        'FTX-SUBACCOUNT' => "Quant-Funding"}
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
