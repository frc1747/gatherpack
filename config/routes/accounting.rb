# Always drawn; the controllers refuse while the accounting feature is off.
namespace :accounting do
  # The one redirect URI registered with Intuit.
  get "quickbooks/callback", to: "quickbooks_connections#callback"
  resources :connections, only: [] do
    get :connect, on: :member, controller: "quickbooks_connections"
    # The GET (also Intuit's Disconnect URL) asks; the POST disconnects.
    get :disconnect, on: :member, controller: "quickbooks_connections"
    post :disconnect, on: :member, controller: "quickbooks_connections", action: "revoke"
    post :sync, on: :member, controller: "syncs"
    post :full_sync, on: :member, controller: "syncs"
    resources :records, only: %i[ index show ]
    # File sources: Upload shows a preview; Apply replaces the records.
    resources :uploads, only: %i[ new create show ] do
      post :apply, on: :member
      get :template, on: :collection
    end
    resources :customers, only: %i[ index show ] do
      get :candidates, on: :member
    end
  end
  resources :customer_links, only: %i[ create destroy ] do
    post :confirm_all, on: :collection
  end
  # "Not this person" on a suggestion.
  resources :customer_dismissals, only: %i[ create ]
end
namespace :accounting do
  resources :rules do
    post :evaluate, on: :member
    post :duplicate, on: :member
    get :export, on: :member
  end
end
scope "people/:person_id", as: :person do
  get "accounting", to: "accounting/people#show", as: :accounting
  get "accounting/statement", to: "accounting/statements#show", as: :accounting_statement
end
