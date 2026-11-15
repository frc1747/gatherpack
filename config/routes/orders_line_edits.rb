# An approver's edit to an item before deciding (spec §3.3). Kept apart
# from the requester's lines routes so each has its own controller.
namespace :orders do
  resources :requests, only: [] do
    resources :line_edits, only: :update
  end
end
