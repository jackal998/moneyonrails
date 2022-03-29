class WebhookController < ApplicationController
  protect_from_forgery except: :receiver

  def receiver
  #   message = JSON.parse(request.body.read)

  #   puts message
    puts params["name"]

    render plain: 'Response Saved', status: 200
  end
end
