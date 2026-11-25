# Tracked units and machines (inventory spec §3.15): a page for each unit
# action, and Install a part on a machine's page. The actions themselves
# are the POST member routes in inventory.rb.
namespace :inventory do
  get "units/:id/:act", to: "units#action_form", as: :unit_action_form,
    constraints: { act: /install|take_off|move|check|mark_for_repair|repaired|retire/ }
  resources :machines, only: [] do
    member do
      post :install
    end
  end
  # The places of one place type that parts get installed on.
  get "machines/type/:type_id", to: "machines#index", as: :machine_type
end
