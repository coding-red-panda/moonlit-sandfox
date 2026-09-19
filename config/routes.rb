Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Battle.net authentication (see docs/adr/002-authentication.md).
  # The redirect to Battle.net is a POST so it carries CSRF protection.
  get 'login' => 'authentication#login', as: :login
  post 'auth/battle_net' => 'authentication#create', as: :battle_net_auth
  get 'callback' => 'authentication#callback', as: :callback
  delete 'logout' => 'authentication#destroy', as: :logout

  # Defines the root path route ("/")
  root 'authentication#login'
end
