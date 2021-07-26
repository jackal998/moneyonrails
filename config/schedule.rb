# 分鐘 1～59
# 小時 0～23
# 日 1～31
# 月 1～12
# 0～6（0表示星期天）
env :PATH, ENV['PATH']
set :output, "#{path}/log/cron.log"
set :environment, :development

every '1 * * * *' do
  rake "dev:fetch_history_rate"
end

every '*/3 * * * *' do
  rake "dev:get_funding_infos"
end