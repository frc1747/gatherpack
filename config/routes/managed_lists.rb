# Managed lists (GatherPack::ManagedLists): one screen per registered list.
get "lists/:list" => "managed_lists#index", :as => :managed_list
scope "lists/:list", as: :managed_list do
  resources :rows, controller: "managed_lists", only: %i[new create edit update destroy] do
    member do
      patch :move
      patch :retire
      patch :restore
      get :merge
      post :merge, action: :merge_into
    end
  end
end
