# A count item edits its commitment row (checklists spec §11.2). wrapped marks
# the items Checklists::WrapCommitments made from existing commitments, so
# undoing it removes only those.
class AddCommitmentToChecklistItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :checklist_items, :commitment, type: :uuid, foreign_key: true, index: { unique: true }
    add_column :checklist_items, :wrapped, :boolean, null: false, default: false
  end
end
