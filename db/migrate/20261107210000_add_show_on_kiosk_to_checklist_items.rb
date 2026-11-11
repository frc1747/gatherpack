# An item an organizer chose to list on the time kiosk while it isn't done.
class AddShowOnKioskToChecklistItems < ActiveRecord::Migration[8.1]
  def change
    add_column :checklist_items, :show_on_kiosk, :boolean, default: false, null: false
  end
end
