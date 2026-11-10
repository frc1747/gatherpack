class AddIntakePlacementAndKioskFields < ActiveRecord::Migration[8.1]
  def change
    # What placement added when the application was approved, and by whom.
    add_column :membership_applications, :intake_placement, :jsonb
    # Person fields the registration's kiosk asks (its first-step questions).
    add_column :intake_registrations, :kiosk_field_ids, :uuid, array: true, default: [], null: false
  end
end
