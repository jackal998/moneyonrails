import Decimal from 'decimal.js';

function gridreadyFn( jQuery ) {

    var grid_setting = document.getElementById("grid_setting_coin_name");

    grid_setup(grid_setting)

    function grid_setup(grid_setting) {
        if (!grid_setting) {return};
        var lower_limit = document.getElementById("lower_limit");
        var upper_limit = document.getElementById("upper_limit");
        var grids = document.getElementById("grids");
        var grid_gap = document.getElementById("grid_setting_grid_gap");
        var input_USD_amount = document.getElementById("input_USD_amount");
        var input_spot_amount = document.getElementById("input_spot_amount");
        var input_USD_detail = document.getElementById("input_USD_detail");
        var input_spot_detail = document.getElementById("input_spot_detail");
        var market_price = document.getElementById("market_price");
        var pricestep = document.getElementById("pricestep");
        var threshold = document.getElementById("threshold");
        var order_size = document.getElementById("order_size");
        
        lower_limit.onchange = function() {checkValue("lower_limit")};
        upper_limit.onchange = function() {checkValue("upper_limit")};
        grids.onchange = function() {checkValue("grids")};
        order_size.onchange = function() {checkValue("order_size")};
        input_USD_amount.onchange = function() {checkValue("input_USD_amount")};
        input_spot_amount.onchange = function() {checkValue("input_spot_amount")};
        market_price.onchange = function() {checkValue("market_price")};

        function checkValue(name) {
          var lower_value = new Decimal(lower_limit.value);
          var upper_value = new Decimal(upper_limit.value);

          var price_step = new Decimal(pricestep.value);
          var size_step = new Decimal(order_size.step);
          var size_value = new Decimal(order_size.value);

          var grids_value = new Decimal(grids.value);
          var gap_value = new Decimal(grid_gap.value);

          var market_value = new Decimal(market_price.value);
          var usd_in_value = new Decimal(input_USD_amount.value);
          var spot_in_value = new Decimal(input_spot_amount.value);
          var spot_step = new Decimal(input_spot_amount.step);
          var threshold_value = new Decimal(threshold.value);

          function validate(name) {
            if (grids_value.lt('2')) {grids_value = new Decimal('2')};
            if (lower_value.lt(lower_limit.min)) {lower_value = new Decimal(lower_limit.min)};
            if (size_value.lt(size_step)) {size_value = size_step};

            switch (name) {
              case 'lower_limit':
                if (lower_value.gte(upper_value)) {
                  upper_value = lower_value.add(price_step);
                } else {
                  if (lower_value.lte(new Decimal('0'))) {
                    lower_value = new Decimal('0');
                  }
                }
                break;
              case 'upper_limit':
                if (upper_value.lte(lower_value)) {
                  if (upper_value.sub(price_step).isNeg()) {
                    upper_value = lower_value.add(price_step);
                  } else {
                    lower_value = upper_value.sub(price_step);
                  }
                }
                break;
              default:
                console.log(`It's ${name}.`);
            }
            grids.value = grids_value.toFixed();
            upper_limit.value = upper_value.toFixed();
            lower_limit.value = lower_value.toFixed();
            order_size.value = size_value.toFixed();
          }
          
          function configcalc(name) {
            // calc upper_value & gap_value
            var max_grids = upper_value.sub(lower_value).div(price_step).add('1');
            if (grids_value.gt(max_grids)) {grids_value = max_grids};

            gap_value = upper_value.sub(lower_value).div(price_step).divToInt(grids_value.sub('1')).mul(price_step);
            upper_value = lower_value.add(grids_value.sub('1').mul(gap_value))
            grid_gap.value = gap_value.toFixed();
            upper_limit.value = upper_value.toFixed();
            grids.value = grids_value.toFixed();
            // end calc upper_value & gap_value
            
            // calc sell/buy grids
            var sell_grids = new Decimal('0');
            var sell_grids_USD_required = new Decimal('0');
            var buy_grids = new Decimal('0');
            var buy_grids_USD_required = new Decimal('0');

            var market_on_grid_value = market_value.sub(lower_value).toNearest(gap_value, Decimal.ROUND_HALF_UP).add(lower_value);

            if (market_on_grid_value.gte(upper_value)) {
              buy_grids = upper_value.sub(lower_value).div(gap_value);
            } else if (market_on_grid_value.gt(lower_value)) {
              buy_grids = market_on_grid_value.sub(lower_value).div(gap_value);
            }

            if (market_on_grid_value.lt(lower_value)) {
              sell_grids = upper_value.sub(lower_value).div(gap_value).add('1');
            } else if (market_on_grid_value.lt(upper_value)) {
              sell_grids = upper_value.sub(market_on_grid_value).div(gap_value);
            }
            // end calc sell/buy grids

            var setting_spot_required = new Decimal('0');
            var setting_usd_required = new Decimal('0');
            var spot_required = new Decimal('0');
            var usd_required = new Decimal('0');
            var spot_inuse = new Decimal('0');

            function usdcalc(size_value) {
              setting_spot_required = sell_grids.mul(size_value);
              setting_usd_required = buy_grids.mul(buy_grids.sub('1')).div('2').mul(gap_value).add(buy_grids.mul(lower_value)).mul(size_value);
// console.log(`sell_grids : ${sell_grids.toFixed(2)}`);
// console.log(`buy_grids : ${buy_grids.toFixed(2)}`);
// console.log(`setting_spot_required : ${setting_spot_required.toFixed(2)}`);
// console.log(`setting_usd_required : ${setting_usd_required.toFixed(2)}`);
// console.log(`size_value : ${size_value.toFixed(2)}`);
              if (spot_in_value.lt(setting_spot_required)) {
                spot_required = setting_spot_required.sub(spot_in_value)
                spot_inuse = spot_in_value
              } else {
                spot_required = new Decimal('0');
                spot_inuse = setting_spot_required
              }
// console.log(`spot_required : ${spot_required.toFixed(2)}`);
              usd_required = setting_usd_required.add(spot_required.mul(market_on_grid_value));
              console.log(`usdcalc: usd_required : ${usd_required.toFixed(2)}`);              
              return usd_required
            }
            
            usd_required = usdcalc(size_value)

            if (name == 'input_USD_amount') {
// console.log(usd_in_value.toFixed(2));
              if (usd_in_value.gt(usd_required)) {
                size_value = size_value.add(size_step);
              } else if (usd_in_value.lt(usd_required) && size_value.gt(size_step)) {
                size_value = size_value.sub(size_step);
              }
              order_size.value = size_value.toNearest(size_step, Decimal.ROUND_HALF_UP);
              usd_required = usdcalc(size_value)
            }
            
            input_USD_amount.value = usd_required.toFixed(2);
// console.log('===========================');
            if (usd_required.gt(input_USD_amount.max) || usd_required.lt(input_USD_amount.min)) {
              input_USD_amount.classList.add("is-invalid");
              input_USD_amount.setAttribute('title', '最大金額 ' + input_USD_amount.max + ' USD');
              input_USD_detail.innerHTML = '最大金額 ' + input_USD_amount.max.toFixed(2) + ' USD';
            } else {
              input_USD_amount.classList.remove("is-invalid");
              input_USD_amount.setAttribute('title', '');
              input_USD_detail.innerHTML = setting_usd_required.toFixed(2) + ' USD + ' + spot_required.toNearest(spot_step) + ' ' + grid_setting.value;
            }

            if (spot_in_value.gt(input_spot_amount.max) || spot_in_value.lt(input_spot_amount.min)) {
              input_spot_amount.classList.add("is-invalid");
              input_spot_amount.setAttribute('title', '最大數量 ' + input_spot_amount.max + ' ' + grid_setting.value);
            } else {
              input_spot_amount.classList.remove("is-invalid");
              input_spot_amount.setAttribute('title', '');
            }
            input_spot_detail.innerHTML = '使用 ' + spot_inuse.toNearest(spot_step) + ' ' + grid_setting.value;
          };
          validate(name);
          configcalc(name);
        }

        console.log("Yo!");
    };
};

$(window).on("load", gridreadyFn);
$(window).on("turbolinks:load", gridreadyFn);