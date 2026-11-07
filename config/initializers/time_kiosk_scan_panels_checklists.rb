# Named to load after time_kiosk_scan_panels.rb, which adds
# TimeKiosk.register_scan_panel.
Rails.application.config.to_prepare do
  ChecklistItemsController.prepend(Checklists::KioskItemParams)
  TimeKiosk.register_scan_panel(:checklists, partial: "checklists/kiosk_still_need")
end
