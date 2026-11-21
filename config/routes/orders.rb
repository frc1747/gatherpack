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
      post :duplicate
      post :follow
      delete :follow, action: :unfollow
      post :comment
      post :mark_all_received, to: "deliveries#mark_all_request"
    end
    resources :lines, only: %i[create update destroy] do
      member do
        post :backorder, controller: "buyer_lines"
        post :change_quantity, controller: "buyer_lines"
        post :split, controller: "buyer_lines"
        post :cancel, controller: "buyer_lines"
        post :mark_received, to: "line_receipts#mark_received"
        post :resolve, to: "line_receipts#resolve"
        post :reallocate, to: "reallocations#create"
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
      post :mark_all_received, to: "deliveries#mark_all_purchase"
      post :make_vendor
    end
  end
  resources :deliveries, only: :index
  resources :vendors do
    collection do
      get :pattern_test
    end
  end
  resources :funding_sources do
    member do
      get :report
    end
  end
  resources :reports, only: %i[index show]
  resource :settings, only: %i[show update]
  resources :approval_steps, only: %i[index new create edit update] do
    member do
      patch :move
      patch :retire
      patch :restore
    end
  end
end
