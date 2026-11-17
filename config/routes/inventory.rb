# Inventory (spec §3). Drawn whether or not the feature is on; every
# inventory controller turns requests away while feature_inventory is off.
namespace :inventory do
  root "search#index"
  get "stock", to: "search#index", as: :stock
  resources :items do
    resource :tracking, controller: "item_tracking", only: %i[create destroy]
    resource :readings, controller: "item_readings", only: %i[edit update]
    resources :sources, controller: "item_sources", except: %i[index show]
  end
  resources :locations, path: "places" do
    member do
      get :count
      post :count, action: :save_count
    end
  end
  get "labels", to: "labels#show", as: :labels
  resource :import, only: %i[new create]
  resources :movements, path: "changes", only: %i[index new create] do
    member do
      post :undo
    end
  end
  get "setup", to: "setup#show", as: :setup
  patch "setup", to: "setup#update"
  get "reorder", to: "reorder#index", as: :reorder
  post "reorder", to: "reorder#run"
  resources :units do
    member do
      post :install
      post :take_off
      post :move
      post :check
      post :mark_for_repair
      post :repaired
      post :retire
    end
  end
  resources :unit_events, only: [] do
    member do
      post :undo
    end
  end
  resources :machines, only: %i[index show]
end
