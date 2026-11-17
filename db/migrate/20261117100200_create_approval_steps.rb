# Approval steps become rows, with their approvers as badge and team rows,
# replacing the orders_approval_steps JSON setting. Each step keeps its key,
# so approvals already given still match it. An approver line whose badge
# or team isn't found reached nobody before; it is left out, with a warning.
# A first step with a minimum gets 0, also with a warning: every request
# needs the first step.
class CreateApprovalSteps < ActiveRecord::Migration[8.1]
  def up
    create_table :approval_steps, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :minimum_cents, null: false, default: 0
      t.timestamps
    end
    add_index :approval_steps, "lower(name)", unique: true
    add_index :approval_steps, :key, unique: true

    create_table :approval_step_approvers, id: :uuid do |t|
      t.references :approval_step, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :badge, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # Null reaches every team. Deleting the team deletes the row rather
      # than widening it to every team.
      t.references :team, foreign_key: { on_delete: :cascade }, type: :uuid
      t.timestamps
    end
    add_index :approval_step_approvers, %i[approval_step_id badge_id team_id], unique: true,
      name: "index_approval_step_approvers_uniqueness"

    ApprovalStep.reset_column_information
    ApprovalStepApprover.reset_column_information
    skipped = Orders::Lists.convert_approval_steps!(Orders::Lists.stored_setting(:orders_approval_steps))
    skipped.each do |line|
      say "Approval steps: #{line}"
      Rails.logger.warn("Approval steps: #{line}")
    end
    Orders::Lists.forget_setting(:orders_approval_steps)
  end

  def down
    Orders::Lists.restore_setting(:orders_approval_steps, Orders::Lists.approval_steps_json)
    drop_table :approval_step_approvers
    drop_table :approval_steps
  end
end
