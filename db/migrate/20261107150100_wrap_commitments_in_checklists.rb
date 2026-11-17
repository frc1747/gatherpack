# Shows every existing commitment as a one-item checklist (checklists spec
# §11.1). Only inserts; undoing it removes the wrapper checklists and their
# items, never a commitment.
class WrapCommitmentsInChecklists < ActiveRecord::Migration[8.1]
  def up
    Checklists::WrapCommitments.new.up
  end

  def down
    Checklists::WrapCommitments.new.down
  end
end
