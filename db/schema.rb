# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2021_09_30_080227) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "coins", force: :cascade do |t|
    t.string "name"
    t.decimal "weight"
    t.decimal "minProvideSize"
    t.boolean "have_perp"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "perppriceIncrement"
    t.decimal "perpsizeIncrement"
    t.decimal "spotpriceIncrement"
    t.decimal "spotsizeIncrement"
    t.index ["name"], name: "index_coins_on_name", unique: true
  end

  create_table "current_fund_stats", force: :cascade do |t|
    t.integer "coin_id"
    t.decimal "nextFundingRate"
    t.datetime "nextFundingTime"
    t.decimal "openInterest"
    t.string "market_type"
    t.decimal "spot_price_usd"
    t.decimal "spot_bid_usd"
    t.decimal "spot_ask_usd"
    t.decimal "spot_volume"
    t.decimal "perp_price_usd"
    t.decimal "perp_bid_usd"
    t.decimal "perp_ask_usd"
    t.decimal "perp_volume"
    t.decimal "success_rate_past_48_hrs"
    t.decimal "success_rate_past_week"
    t.decimal "irr_past_week"
    t.decimal "irr_past_month"
    t.decimal "perp_over_spot"
    t.decimal "spot_over_perp"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "rate"
    t.index ["coin_id"], name: "index_current_fund_stats_on_coin_id"
  end

  create_table "funding_orders", force: :cascade do |t|
    t.integer "coin_id"
    t.string "coin_name"
    t.decimal "original_spot_amount"
    t.decimal "original_perp_amount"
    t.decimal "target_spot_amount"
    t.decimal "target_perp_amount"
    t.string "order_status", default: "close"
    t.integer "acceleration", default: 3
    t.decimal "threshold", default: "0.0"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "system", default: false
    t.string "description"
    t.index ["coin_id"], name: "index_funding_orders_on_coin_id"
    t.index ["coin_name"], name: "index_funding_orders_on_coin_name"
    t.index ["order_status"], name: "index_funding_orders_on_order_status"
    t.index ["system"], name: "index_funding_orders_on_system"
  end

  create_table "funding_payments", force: :cascade do |t|
    t.integer "coin_id"
    t.string "coin_name"
    t.decimal "payment"
    t.datetime "time"
    t.decimal "rate"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["coin_id"], name: "index_funding_payments_on_coin_id"
    t.index ["coin_name"], name: "index_funding_payments_on_coin_name"
    t.index ["time"], name: "index_funding_payments_on_time"
  end

  create_table "funding_stats", force: :cascade do |t|
    t.integer "coin_id"
    t.string "coin_name"
    t.decimal "last_1_day_payments", default: "0.0"
    t.decimal "last_1_day_irr", default: "0.0"
    t.decimal "last_3_day_payments", default: "0.0"
    t.decimal "last_3_day_irr", default: "0.0"
    t.decimal "last_7_day_payments", default: "0.0"
    t.decimal "last_7_day_irr", default: "0.0"
    t.decimal "last_14_day_payments", default: "0.0"
    t.decimal "last_14_day_irr", default: "0.0"
    t.decimal "last_30_day_payments", default: "0.0"
    t.decimal "last_30_day_irr", default: "0.0"
    t.decimal "last_60_day_payments", default: "0.0"
    t.decimal "last_60_day_irr", default: "0.0"
    t.decimal "last_90_day_payments", default: "0.0"
    t.decimal "last_90_day_irr", default: "0.0"
    t.decimal "historical_payments", default: "0.0"
    t.decimal "historical_irr", default: "0.0"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["coin_id"], name: "index_funding_stats_on_coin_id"
    t.index ["coin_name"], name: "index_funding_stats_on_coin_name"
  end

  create_table "grid_orders", force: :cascade do |t|
    t.integer "grid_setting_id"
    t.decimal "ftx_order_id"
    t.string "market", default: ""
    t.string "order_type", default: ""
    t.string "side", default: ""
    t.decimal "price"
    t.decimal "size"
    t.string "status", default: "new"
    t.decimal "filledSize"
    t.decimal "remainingSize"
    t.decimal "avgFillPrice"
    t.datetime "createdAt"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "market_name"
    t.index ["ftx_order_id"], name: "index_grid_orders_on_ftx_order_id"
    t.index ["grid_setting_id"], name: "index_grid_orders_on_grid_setting_id"
    t.index ["market_name"], name: "index_grid_orders_on_market_name"
    t.index ["status"], name: "index_grid_orders_on_status"
  end

  create_table "grid_settings", force: :cascade do |t|
    t.decimal "lower_limit"
    t.boolean "dyn_lower_limit", default: false
    t.decimal "upper_limit"
    t.boolean "dyn_upper_limit", default: false
    t.integer "grids"
    t.decimal "grid_gap"
    t.boolean "constant_gap", default: true
    t.decimal "input_USD_amount"
    t.decimal "input_spot_amount"
    t.decimal "input_totalUSD_amount"
    t.decimal "trigger_price"
    t.decimal "stop_loss_price"
    t.decimal "take_profit_price"
    t.decimal "threshold", default: "0.0"
    t.string "status", default: "waiting"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "order_size"
    t.string "description"
    t.string "market_name"
    t.decimal "price_step"
    t.decimal "size_step"
    t.index ["market_name"], name: "index_grid_settings_on_market_name"
    t.index ["status"], name: "index_grid_settings_on_status"
  end

  create_table "rates", force: :cascade do |t|
    t.string "name"
    t.datetime "time"
    t.decimal "rate"
    t.integer "coin_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["coin_id"], name: "index_rates_on_coin_id"
    t.index ["name"], name: "index_rates_on_name"
  end

end
