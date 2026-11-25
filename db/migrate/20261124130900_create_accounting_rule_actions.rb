class CreateAccountingRuleActions < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_rule_actions, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :accounting_rules, on_delete: :cascade }
      t.string :action, null: false
      t.jsonb :condition, null: false, default: {}
      t.references :badge, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :person_field, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :write
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
