class CreateAccountingRuleMilestones < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_rule_milestones, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :accounting_rules, on_delete: :cascade }
      t.string :name, null: false
      t.date :due_on, null: false
      t.bigint :balance_at_most_cents
      t.integer :balance_at_most_percent
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
