class ApplicationController < ActionController::Base
  def ftx_wallet_balance(sub_account, coin_name)
    balances = {"totalusdValue" => 0.00}

    ftx_wallet_balances_response = FtxClient.wallet_balances(sub_account)
    if ftx_wallet_balances_response["success"]
      ftx_wallet_balances_response["result"].each do |result|
        balances[result["coin"]] = {"spot_amount" => result["total"], "available_amount" => result["availableWithoutBorrow"], "usdValue" => result["usdValue"]}
        balances["totalusdValue"] += result["usdValue"]
      end
    end

    ["USD", coin_name].each { |c| balances[c] = {"spot_amount" => 0.0, "available_amount" => 0.0, "usdValue" => 0.0} unless balances[c] }

    # 把USD移到最後
    balances["USD"] = balances.delete("USD") if balances["USD"]
    balances
  end

  ROBOT.each do |name, data|
    define_method(:"authenticate_for_#{name}") do
      if current_user.public_send("permission_to_#{name}") == "false"
        error_msg = "沒有使用#{data["zh_name"]}的權限"
      else
        error_msg = "請先建立#{data["zh_name"]}的子帳戶API" unless current_user.send("#{name}_account")
      end

      redirect_to authenticated_root_path, flash: {alert: error_msg} if error_msg
    end
  end
end
