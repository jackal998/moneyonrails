Rails.application.routes.draw do
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

  # devise_for :managers
  devise_for :users
  
  devise_scope :user do
    authenticated :user do
      root 'devise/registrations#edit', as: :authenticated_root
    end

    unauthenticated do
      root 'devise/sessions#new', as: :unauthenticated_root
    end
  end
  root :to => redirect('/users/sign_in')
  # get "*path", to: redirect('/funding')
end
