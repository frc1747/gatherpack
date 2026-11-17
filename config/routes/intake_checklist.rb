# Bulk application decisions, gated by checklist completion (needs :intake
# and :checklists; the controller checks the features).
scope module: :intake, as: :intake do
  resources :teams, only: [] do
    post "applications/bulk" => "bulk_decisions#create", :as => :bulk_decisions
  end
end
