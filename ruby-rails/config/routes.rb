Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "hello", to: "hello#index"

  namespace :admin do
    resources :content, only: [:index, :show, :new, :create, :edit, :update, :destroy], controller: "content", constraints: { id: /\d+/ } do
      member do
        post :commit
        post :publish
        get :history
      end
      resources :versions, only: [:show], controller: "versions", constraints: { id: /\d+/ } do
        member do
          post :revert
        end
      end
    end
    resources :branches, only: [:index, :new, :create, :destroy], constraints: { id: /\d+/ }
    post "switch-branch", to: "branches#switch", as: :switch_branch
  end

  root to: redirect("/admin/content")

  # Public content route — must be last to avoid intercepting other paths
  get "/:slug", to: "public/content#show", as: :public_content, constraints: { slug: /[a-z0-9]+(-[a-z0-9]+)*/ }
end
