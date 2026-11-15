# Always drawn; the controllers check the feature (default off).
resources :checklists do
  member do
    get :copy, action: :copy_form
    post :copy
    post :preview
    post :refresh
    post :restore
  end
  resources :checklist_items, path: "items", except: %i[index show] do
    post :preview, on: :collection
  end
  resources :checklist_rules, path: "rules", only: %i[create destroy]
  resources :checklist_grants, path: "grants", only: %i[create destroy]
  resources :checklist_organizers, path: "organizers", only: %i[create destroy]
  resources :checklist_excuses, path: "excuses", only: %i[new create destroy]
  resources :checklist_attestations, path: "attestations", only: %i[create destroy]
  resources :checklist_lists, path: "lists", only: %i[show create]
end
get "people/:person_id/checklists", to: "person_checklists#show", as: :person_checklists
