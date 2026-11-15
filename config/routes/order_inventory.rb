# Order receiving into inventory (orders spec §5). Drawn whether or not
# the features are on; the controllers turn requests away unless both are.
namespace :order_inventory do
  resources :items, only: :index
  resources :reorder_drafts, only: %i[new create]
end
