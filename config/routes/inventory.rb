# Inventory (spec §3). Drawn whether or not the feature is on; every
# inventory controller turns requests away while feature_inventory is off.
namespace :inventory do
  root "search#index"
  resources :items do
    member do
      post :tracking, action: :start_tracking
      delete :tracking, action: :stop_tracking
    end
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
  get "reorder", to: "reorder#index", as: :reorder
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
