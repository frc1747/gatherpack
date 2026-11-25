class CreateAccountingRuleBadgeGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_rule_badge_grants, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :accounting_rules, on_delete: :cascade }, index: false
      t.references :badge, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :amounts, null: false, default: false
      t.boolean :bill, null: false, default: false

      t.timestamps
    end

    add_index :accounting_rule_badge_grants, %i[ rule_id badge_id ], unique: true
  end
end
