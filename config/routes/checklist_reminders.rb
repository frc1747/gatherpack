# Always drawn; the controllers check the feature (default off).
resources :checklists, only: [] do
  resources :checklist_reminders, path: "reminders", only: %i[new create]
  resource :checklist_reminder_settings, path: "reminder_settings", only: :update
end
