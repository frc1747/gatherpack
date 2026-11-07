# A registration's checklist (the column came with intake, unlinked until
# checklists existed), and which checklist items a shared kiosk screen may
# list as still to do (none until an organizer says so).
class LinkIntakeRegistrationsToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_index :intake_registrations, :checklist_id
    add_foreign_key :intake_registrations, :checklists, column: :checklist_id
    add_column :checklist_items, :show_on_kiosk, :boolean, default: false, null: false
  end
end
