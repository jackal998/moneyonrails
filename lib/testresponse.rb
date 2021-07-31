collateral = data["result"]["collateral"]
freeCollateral = data["result"]["freeCollateral"]
totalAccountValue = data["result"]["totalAccountValue"]
totalPositionSize = data["result"]["totalPositionSize"]
f_costs=0
f_realizedPnls=0
f_collateralUsed=0
data["result"]["positions"].each { |p| p.to_hash.each { |k,v| f_costs += v if k == "cost"}}
data["result"]["positions"].each { |p| p.to_hash.each { |k,v| f_realizedPnls += v if k == "realizedPnl"}}
data["result"]["positions"].each { |p| p.to_hash.each { |k,v| f_collateralUsed += v if k == "collateralUsed"}}
collateral
freeCollateral
totalAccountValue
totalPositionSize
f_costs
f_realizedPnls
f_collateralUsed

# Test 1
input 10U
USD = 9.21
BAO = 0.79
U_sum = BAO + USD = 10
U_calc1 = BAO * 0.8 + USD  => 9.842     # U_calc1
U_calc2 = BAO * 0.85 + USD => 9.8815    # U_calc2

# Buy 1000 BAO
collateral         => 9.882212665247    # U_calc2
freeCollateral     => 9.842758979056    # U_calc1
totalAccountValue  => 9.882212665247    # U_calc2
totalPositionSize  => 0.0
f_costs            => 0
f_realizedPnls     => 0    # U_calc2
f_collateralUsed   => 0                 # U_calc1


# Sell BAO-PERP -0.79 U
collateral         => 9.882506895494625 # U_calc2
freeCollateral     => 9.759909725642    # U_calc1
totalAccountValue  => 9.878506895494626 # U_calc2
totalPositionSize  => 0.791
f_costs            => -0.791
f_realizedPnls     => -0.004            # U_calc2
f_collateralUsed   => 0.0791            # U_calc1

# Test 2
input 10U
USD = 6.02
BAO = 3.95
U_sum = BAO + USD = 9.97
U_calc1 = BAO * 0.8 + USD  => 9.18      # U_calc1
U_calc2 = BAO * 0.85 + USD => 9.3775    # U_calc2

collateral        => 9.39881238586625   # U_calc2
freeCollateral    => 8.78724405258      # U_calc1
totalAccountValue => 9.38006238586625   # U_calc2
totalPositionSize => 3.95375
f_costs           => -3.95375
f_realizedPnls    => -0.01875           # U_calc2
f_collateralUsed  => 0.395375           # U_calc1

# Test 3
input 9.97U
USD = 4.45
BAO = 5.52
U_sum = BAO + USD = 9.97
U_calc1 = BAO * 0.8 + USD  => 8.866     # U_calc1
U_calc2 = BAO * 0.85 + USD => 9.142     # U_calc2

collateral        => 9.1350168822695
freeCollateral    => 8.451342402136
totalAccountValue => 9.1537668822695
totalPositionSize => 3.94375
f_costs           => -3.94375
f_realizedPnls    => -0.00875
f_collateralUsed  => 0.394375


input 9.95U
USD = 4.43
BAO = 5.52
U_sum = BAO + USD = 9.97
U_calc1 = BAO * 0.8 + USD  => 8.846     # U_calc1
U_calc2 = BAO * 0.85 + USD => 9.122     # U_calc2


collateral         => 9.12401450477325
freeCollateral     => 8.293634683316
totalAccountValue  => 9.12426450477325
totalPositionSize  => 5.54225
f_costs            => -5.54225
f_realizedPnls     => -0.02725
f_collateralUsed   => 0.554225





Real
USD = 1386.72
BAO = 1823.35
ALPHA = 1814.46
SUSHI = 803.84
U_sum = BAO + ALPHA + SUSHI - USD
U_calc1 = BAO * 0.8 + ALPHA * 0.85 + SUSHI * 0.9 - USD
U_calc2 = BAO * 0.85 + ALPHA * 0.9 + SUSHI * 0.95 - USD

BAO 0.8
ALPHA 0.85
SUSHI 0.9

U_sum  =           => 3054.9299999999994
U_calc1=           => 2337.7070000000003
U_calc2=           => 2559.7895

collateral         => 2503.7037882398213
freeCollateral     => 1666.7872497161331
totalAccountValue  => 2560.7025382398215
totalPositionSize  => 4431.73725
f_costs            => -4431.73725
f_realizedPnls     => -1197.5081024799997
f_collateralUsed   => 443.173725

USD    = 1386.72   => 1386.72
BAO    = 1823.35   => 1823.35
ALPHA  = 1814.46   => 1814.46
SUSHI  = 803.84    => 803.84

data = {"success"=>true,
 "result"=>
  {"username"=>"fulyjackal998@gmail.com/fuly-funding",
   "collateral"=>2503.7037882398213,
   "freeCollateral"=>1666.7872497161331,
   "totalAccountValue"=>2560.7025382398215,
   "totalPositionSize"=>4431.73725,
   "initialMarginRequirement"=>0.1,
   "maintenanceMarginRequirement"=>0.03,
   "marginFraction"=>0.5778100987913536,
   "openMarginFraction"=>0.38433266628707313,
   "liquidating"=>false,
   "backstopProvider"=>false,
   "positions"=>
    [{"future"=>"ALPHA-PERP",
      "size"=>3000.0,
      "side"=>"sell",
      "netSize"=>-3000.0,
      "longOrderSize"=>0.0,
      "shortOrderSize"=>0.0,
      "cost"=>-1805.4,
      "entryPrice"=>0.6018,
      "unrealizedPnl"=>0.0,
      "realizedPnl"=>-653.83113867,
      "initialMarginRequirement"=>0.1,
      "maintenanceMarginRequirement"=>0.03,
      "openSize"=>3000.0,
      "collateralUsed"=>180.54,
      "estimatedLiquidationPrice"=>8.693247375834662},
     {"future"=>"BAO-PERP",
      "size"=>2321000.0,
      "side"=>"sell",
      "netSize"=>-2321000.0,
      "longOrderSize"=>0.0,
      "shortOrderSize"=>0.0,
      "cost"=>-1827.20725,
      "entryPrice"=>0.00078725,
      "unrealizedPnl"=>0.0,
      "realizedPnl"=>-846.13849161,
      "initialMarginRequirement"=>0.1,
      "maintenanceMarginRequirement"=>0.03,
      "openSize"=>2321000.0,
      "collateralUsed"=>182.720725,
      "estimatedLiquidationPrice"=>0.007670855702253657},
     {"future"=>"SUSHI-PERP",
      "size"=>100.0,
      "side"=>"sell",
      "netSize"=>-100.0,
      "longOrderSize"=>0.0,
      "shortOrderSize"=>0.0,
      "cost"=>-799.13,
      "entryPrice"=>7.9913,
      "unrealizedPnl"=>0.0,
      "realizedPnl"=>302.4615278,
      "initialMarginRequirement"=>0.1,
      "maintenanceMarginRequirement"=>0.03,
      "openSize"=>100.0,
      "collateralUsed"=>79.913,
      "estimatedLiquidationPrice"=>499.74154966099894}],
   "takerFee"=>0.00064505,
   "makerFee"=>0.0,
   "leverage"=>10.0,
   "positionLimit"=>nil,
   "positionLimitUsed"=>nil,
   "useFttCollateral"=>true,
   "chargeInterestOnNegativeUsd"=>false,
   "spotMarginEnabled"=>false,
   "spotLendingEnabled"=>false}}