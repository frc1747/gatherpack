# Orders with the Ledger and Budgets features (spec §6): recording a
# purchase in a ledger later, and linking a funding source to a Budget.
namespace :orders do
  resources :purchases, only: [] do
    resource :ledger_entry, only: :create, controller: "purchase_ledger_entries"
  end
  resources :funding_sources, only: [] do
    resource :budget, only: %i[edit update], controller: "funding_source_budgets"
  end
end
