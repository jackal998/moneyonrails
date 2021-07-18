require 'csv'

namespace :dev do

  task :import_coins_csv_file => :environment do

    success = 0
    failed_records = []

  	CSV.foreach("#{Rails.root}/tmp/coin_seed.csv", headers: true) do |row|
  	  coin = Coin.new(row.to_hash)
      if coin.save
        success += 1
      else
        failed_records << [row, coin]
      end
  	end

    puts "總共匯入 #{success} 筆，失敗 #{failed_records.size} 筆"
    failed_records.each do |record|
      puts "#{record[0]} ---> #{record[1].errors.full_messages}"
    end
  end
end