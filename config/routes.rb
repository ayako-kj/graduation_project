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
  resources :staffs do
    member do
      patch :move_up
      patch :move_down
      post :regenerate_token
    end
    collection do
      get :hope_urls
      get :hope_qrcodes
      get :special_date_urls
      get :special_date_qrcodes
      get :combined_qrcodes
    end
  end

  # 職員向け希望休入力（トークン認証・ログイン不要）
  get  "/hope",      to: "staff_leave_requests#index", as: :staff_leave_input
  post "/hope/save", to: "staff_leave_requests#save",  as: :save_staff_leave_input

  # 職員向け特定日入力（トークン認証・ログイン不要）
  get    "/special",      to: "staff_special_dates#index",   as: :staff_special_dates
  post   "/special",      to: "staff_special_dates#create",  as: :create_staff_special_date
  get    "/special/:id/edit", to: "staff_special_dates#edit",   as: :edit_staff_special_date
  patch  "/special/:id",  to: "staff_special_dates#update",  as: :update_staff_special_date
  delete "/special/:id",  to: "staff_special_dates#destroy", as: :destroy_staff_special_date
  resources :staff_types, only: %i[index create destroy] do
    member do
      patch :move_up
      patch :move_down
    end
  end
  resources :employment_types, only: %i[create update destroy]
  resources :placement_rules
  resources :special_dates
  resources :temporary_closed_dates
  resources :leave_requests
  resources :assignments
  resources :mobile_libraries do
    resources :mobile_library_routes, path: :routes
  end

  resources :shifts, only: [:index, :update] do
    collection do
      post :generate
      post :confirm
      post :restore
      post :suppress_errors
      post :restore_errors
      delete :destroy_group
      get :download
      get :export
    end
  end

  resources :actual_leaves, only: [:index] do
    collection do
      post :save
    end
  end

  get "privacy-policy", to: "pages#privacy_policy", as: :privacy_policy
  get "help",           to: "pages#help",           as: :help
  get "terms",          to: "pages#terms",           as: :terms

  root "pages#home"
end
