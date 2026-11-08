# Always drawn; the controllers check the feature (default off).
scope "housekeeping", as: :housekeeping do
  get "purges/:key", to: "housekeeping_purges#show", as: :purge
  post "purges/:key", to: "housekeeping_purges#create"
  get ":type", to: "housekeeping#index", as: :list
  post ":type/preview", to: "housekeeping#preview", as: :preview
  post ":type/default", to: "housekeeping#save_default", as: :default
  post ":type", to: "housekeeping#apply", as: :apply
end
get "teams/:team_id/move_people", to: "team_moves#new", as: :team_move_people
post "teams/:team_id/move_people/preview", to: "team_moves#preview", as: :preview_team_move_people
post "teams/:team_id/move_people", to: "team_moves#create"
