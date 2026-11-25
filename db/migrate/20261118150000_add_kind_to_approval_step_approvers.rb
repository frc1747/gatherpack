# An approver row names holders of a badge (as before), the managers of a
# team, or the managers of the request's own team. Undoing it drops the
# rows that aren't badge rows, which the old columns can't hold.
class AddKindToApprovalStepApprovers < ActiveRecord::Migration[8.1]
  def up
    add_column :approval_step_approvers, :kind, :string, null: false, default: "badge"
    # Deleting the team deletes the row rather than leaving it naming nobody.
    add_reference :approval_step_approvers, :manager_team, type: :uuid, foreign_key: { to_table: :teams, on_delete: :cascade }
    change_column_null :approval_step_approvers, :badge_id, true
    remove_index :approval_step_approvers, name: "index_approval_step_approvers_uniqueness"
    add_index :approval_step_approvers, %i[approval_step_id kind badge_id manager_team_id team_id], unique: true,
      nulls_not_distinct: true, name: "index_approval_step_approvers_uniqueness"
  end

  def down
    execute "DELETE FROM approval_step_approvers WHERE kind <> 'badge' OR badge_id IS NULL"
    remove_index :approval_step_approvers, name: "index_approval_step_approvers_uniqueness"
    add_index :approval_step_approvers, %i[approval_step_id badge_id team_id], unique: true,
      name: "index_approval_step_approvers_uniqueness"
    change_column_null :approval_step_approvers, :badge_id, false
    remove_reference :approval_step_approvers, :manager_team, foreign_key: { to_table: :teams }
    remove_column :approval_step_approvers, :kind
  end
end
