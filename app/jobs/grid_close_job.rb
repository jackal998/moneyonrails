class GridCloseJob < ApplicationJob
  queue_as :default

  def logger
    Logger.new("log/grid_close_job.log")
  end

  def perform(grid_setting_id)
    @grid_setting = GridSetting.find_by_id(grid_setting_id)
    return unless @grid_setting
    return if @grid_setting.status == "closed"
    @grid_setting.update(status: "closing")
    @sub_account = @grid_setting.user.grid_account

    logger.info(@grid_setting.id) { "Closing..." }
    open_orders = FtxClient.open_orders(@sub_account, market: @grid_setting["market_name"])["result"].select { |order| order["createdAt"] > @grid_setting.created_at }

    to_cancel_order_ids = open_orders.pluck("id")
    to_cancel_order_ids.each { |order_id| FtxClient.cancel_order(@sub_account, order_id) }

    @grid_setting.grid_orders.where(ftx_order_id: to_cancel_order_ids).update_all(status: "canceled")
    @grid_setting.update(status: "closed")

    current_redis_keys = ["sub_account:#{@sub_account.id}:grid_setting:#{@grid_setting.id}"]
    current_redis_keys += Redis.new.keys "sub_account:#{@sub_account.id}:grid_setting:#{@grid_setting.id}:*"
    Redis.new.del(current_redis_keys)

    logger.info(@grid_setting.id) { "Closed and total #{to_cancel_order_ids.count} orders canceled OK. See you." }
  end
end
