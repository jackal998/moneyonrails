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

ActiveRecord::Schema.define(version: 2021_07_26_122034) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "coins", force: :cascade do |t|
    t.string "name"
    t.decimal "weight"
    t.decimal "minProvideSize"
    t.boolean "have_perp"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "priceIncrement"
    t.decimal "sizeIncrement"
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
    t.index ["coin_id"], name: "index_current_fund_stats_on_coin_id"
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
