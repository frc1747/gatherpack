# Pickers for settings (Settings.input) and settings shown on a feature's own
# page (Settings.page). See lib/gatherpack/settings_inputs.rb.
require Rails.root.join("lib/gatherpack/settings_inputs").to_s

Rails.application.config.to_prepare do
  SettingsController.include(SettingInputParams)
end
