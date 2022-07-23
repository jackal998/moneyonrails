class Rate < ApplicationRecord
  belongs_to :coin

  validates_uniqueness_of :name, scope: :time

  def self.latest_rates_for_coins
    latest_rate = Coin
      .select("latest_rate.*")
      .joins(<<-SQL)
        JOIN LATERAL (
          SELECT * FROM rates
          WHERE coin_id = coins.id
          ORDER BY time DESC LIMIT 1
        ) AS latest_rate ON TRUE
      SQL

    Rate.from(latest_rate, "rates").order(id: :desc)
  end
end
