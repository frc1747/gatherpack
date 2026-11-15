# Order requests (spec §3). Drawn whether or not the feature is on; every
# orders controller turns requests away while feature_orders is off.
namespace :orders do
  resources :requests do
    member do
      post :submit
      post :resubmit
      post :cancel
      post :close
      post :order_again
      post :follow
      delete :follow, action: :unfollow
      post :comment
    end
    resources :lines, only: %i[create update destroy] do
      member do
        post :backorder
        post :split
        post :cancel
        post :mark_received
        post :resolve
        post :reallocate
      end
      resources :deliveries, only: %i[new create]
    end
    resources :decisions, only: :create
    resources :watchers, only: %i[create destroy]
  end
  resources :approvals, only: :index
  resources :purchases, only: %i[index show new create edit update] do
    collection do
      get :to_buy
    end
    member do
      post :mark_all_received
    end
  end
  resources :deliveries, only: :index
  resources :vendors
  resources :funding_sources do
    member do
      get :report
    end
  end
  resources :reports, only: %i[index show]
end
