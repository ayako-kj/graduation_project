Rails.application.routes.draw do
  devise_for :admins, controllers: { registrations: "admins/registrations" }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  resources :working_day_summaries, only: [:index]
  resources :workday_manual_entries, only: [:index] do
    collection do
      post :save
    end
  end
  resources :staffs
  resources :placement_rules
  resources :special_dates
  resources :leave_requests

  resources :shifts, only: [:index] do
    collection do
      post :generate
      get :download
    end
  end

  get "privacy-policy", to: "pages#privacy_policy", as: :privacy_policy
  get "help",           to: "pages#help",           as: :help
  get "terms",          to: "pages#terms",           as: :terms

  root "pages#home"
end
