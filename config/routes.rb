Rails.application.routes.draw do
  require 'sidekiq/web'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  scope :controller => "fundings", :path => "/funding", :as => "funding" do
    get '/' => :index
    get '/show'   => :show        , :as => "show"
    post '/order' => :createorder , :as => "createorder"
    put '/order'  => :abortorder  , :as => "abortorder"
  end

  scope :controller => "grid", :path => "/grid", :as => "grid" do
    get '/' => :index
    post '/create' => :create  , :as => "create"
    put '/close'   => :close   , :as => "close"
  end
  
  scope :controller => "user", :path => "/sub_account", :as => "sub_account" do
    post '/create' => :createsubaccount, :as => "create"
    delete '/delete' => :deletesubaccount, :as => "delete"
  end

  post '/', :to => 'webhook#receiver'

  # should be authed
  mount Sidekiq::Web => '/sidekiq'

  # devise_for :managers
  devise_for :users
  
  devise_scope :user do
    authenticated :user do
      root 'user#show', :as => "authenticated_root"
    end

    unauthenticated do
      root 'devise/sessions#new', :as => "unauthenticated_root"
    end
  end
end
