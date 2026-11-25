class CreateAccountingRuleResults < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_rule_results, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :accounting_rules, on_delete: :cascade }, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :value, null: false
      t.bigint :amount_cents
      t.jsonb :details, null: false, default: {}
      t.datetime :evaluated_at, null: false
      t.datetime :changed_at, null: false
      t.references :badge_assignment, type: :uuid, foreign_key: { on_delete: :nullify }

      t.timestamps
    end

    add_index :accounting_rule_results, %i[ rule_id person_id ], unique: true
    add_index :accounting_rule_results, %i[ rule_id value ]
  end
end
