# 分鐘 1～59
# 小時 0～23
# 日 1～31
# 月 1～12
# 0～6（0表示星期天）
env :PATH, ENV['PATH']
set :output, "#{path}/log/cron.log"
set :environment, :development

every '3 * * * *' do
  rake "dev:update_funding_payment"
  rake "market:update_infos"
  rake "market:update_funding_infos"
  rake "market:update_rates"
end
