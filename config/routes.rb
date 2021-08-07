Rails.application.routes.draw do
  require 'sidekiq/web'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

  get '/funding', :to => 'fundings#index'
  get '/funding/show', :to => 'fundings#show'
  post '/funding/order', :to => 'fundings#createorder'

  # should be authed
  mount Sidekiq::Web => '/sidekiq'

  root :to => redirect('/funding')
  # get "*path", to: redirect('/funding')
end
