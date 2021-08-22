import Decimal from 'decimal.js';

function gridreadyFn( jQuery ) {

    var grid_setting = document.getElementById("grid_setting_coin_name");

    grid_setup(grid_setting)

    function grid_setup(grid_setting) {
        if (!grid_setting) {
            return;
        }
        var lower_limit = document.getElementById("lower_limit");
        var upper_limit = document.getElementById("upper_limit");
        var grids = document.getElementById("grids");
        var grid_gap = document.getElementById("grid_setting_grid_gap");
        var input_USD_amount = document.getElementById("input_USD_amount");
        var input_spot_amount = document.getElementById("input_spot_amount");
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
          var usd_value = new Decimal(input_USD_amount.value);
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
            if (grids_value.gt(max_grids)) {
              grids_value = max_grids;
            };

            gap_value = upper_value.sub(lower_value).div(price_step).divToInt(grids_value.sub('1')).mul(price_step);
            upper_value = lower_value.add(grids_value.sub('1').mul(gap_value))
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

            // calc USD required
            sell_grids_USD_required = sell_grids.mul(market_on_grid_value);
            buy_grids_USD_required = buy_grids.mul(buy_grids.sub('1')).div('2').mul(gap_value).add(buy_grids.mul(lower_value));

            var usd_step = sell_grids_USD_required.add(buy_grids_USD_required).mul(size_step);
            // end calc USD required

            grids.value = grids_value.toFixed();
            grid_gap.value = gap_value.toFixed();
            upper_limit.value = upper_value.toFixed();
            input_USD_amount.step = usd_step.toFixed(2);

            if (name == 'input_USD_amount') {
              size_value = usd_value.div(usd_step).mul(size_step)
              order_size.value = size_value.toNearest(size_step, Decimal.ROUND_HALF_UP);
            } else {
              usd_value = usd_step.mul(size_value.div(size_step));
              input_USD_amount.value = usd_value.toFixed(2);
            }

            if (usd_value.gt(input_USD_amount.max) || usd_value.lt(input_USD_amount.min)) {
              input_USD_amount.classList.add("is-invalid");
              input_USD_amount.setAttribute('title', '最大金額 ' + input_USD_amount.max + ' USD');
            } else {
              input_USD_amount.classList.remove("is-invalid");
              input_USD_amount.setAttribute('title', '');
            }
          };
          validate(name);
          configcalc(name);
        }

        console.log("Yo!");
    };
};

$(window).on("load", gridreadyFn);
$(window).on("turbolinks:load", gridreadyFn);