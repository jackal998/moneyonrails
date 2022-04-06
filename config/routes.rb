Rails.application.routes.draw do
  devise_for :managers
  devise_for :users
  require 'sidekiq/web'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

  get '/funding', :to => 'fundings#index'
  get '/funding/show', :to => 'fundings#show'
  post '/funding/order', :to => 'fundings#createorder'
  put '/funding/order', :to => 'fundings#abortorder'

  get '/grid', :to => 'grid#index'
  post '/grid/create', :to => 'grid#creategrid'
  put '/grid/close', :to => 'grid#closegrid'
  
  post '/', :to => 'webhook#receiver'

  # should be authed
  mount Sidekiq::Web => '/sidekiq'

  root :to => redirect('/funding')
  # get "*path", to: redirect('/funding')
end
