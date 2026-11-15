# A registration's checklist: the column came with intake, unlinked until
# checklists existed.
class LinkIntakeRegistrationsToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_index :intake_registrations, :checklist_id
    add_foreign_key :intake_registrations, :checklists, column: :checklist_id
  end
end
