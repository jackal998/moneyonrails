class ApplicationController < ActionController::Base
  def ftx_wallet_balance(account_name, coin_name)
    balances = {"totalusdValue" => 0.00}

    ftx_wallet_balances_response = FtxClient.wallet_balances(account_name)
    if ftx_wallet_balances_response["success"] 
      ftx_wallet_balances_response["result"].each do |result|
        balances[result["coin"]] = {"spot_amount" => result["total"], "available_amount" => result["availableWithoutBorrow"], "usdValue" => result["usdValue"]}
        balances["totalusdValue"] += result["usdValue"]
      end
    end    

    ["USD", coin_name].each { |c| balances[c] = {"spot_amount" => 0.0, "available_amount" => 0.0, "usdValue"=>0.0} unless balances[c] }

    # 把USD移到最後
    balances["USD"] = balances.delete("USD") if balances["USD"]
    return balances
  end
end
