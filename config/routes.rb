Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

  get '/funding', :to => 'fundings#index'
  get '/funding/show', :to => 'fundings#show'

  root :to => redirect('/funding')
  # get "*path", to: redirect('/funding')
end
