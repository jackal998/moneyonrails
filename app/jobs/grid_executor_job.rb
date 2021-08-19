class GridExecutorJob < ApplicationJob
  queue_as :default

  def perform(coin_name)
    init_time = Time.now
    (1..10).each do |variable|
      puts "#{init_time} -> #{coin_name} #{variable}"
      sleep(1)
    end
  end
end
