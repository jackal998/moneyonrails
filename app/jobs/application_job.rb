class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  def order_result_to_output(order_result)
    return "" unless order_result
    order_result.select { |k, v| {k => v} if ["market", "type", "side", "price", "size"].include?(k) }.to_s
  end

  def attributes_from_ftx_to_db(ftx_order)
    {"order_type" => ftx_order["type"],
     "side" => ftx_order["side"],
     "price" => ftx_order["price"],
     "size" => ftx_order["size"],
     "status" => ftx_order["status"],
     "filledSize" => ftx_order["filledSize"],
     "remainingSize" => ftx_order["remainingSize"],
     "avgFillPrice" => ftx_order["avgFillPrice"],
     "createdAt" => ftx_order["createdAt"]}
  end
end
