# Always drawn; the controllers refuse while the accounting feature is off.
namespace :accounting do
  # The one redirect URI registered with Intuit.
  get "quickbooks/callback", to: "quickbooks_connections#callback"
  resources :connections, only: [] do
    get :connect, on: :member, controller: "quickbooks_connections"
    get :disconnect, on: :member, controller: "quickbooks_connections"
    post :sync, on: :member, controller: "syncs"
    post :full_sync, on: :member, controller: "syncs"
    resources :records, only: %i[ index show ]
  end
end
