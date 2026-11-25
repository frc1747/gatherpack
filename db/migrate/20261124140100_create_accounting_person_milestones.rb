class CreateAccountingPersonMilestones < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_person_milestones, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :accounting_rules, on_delete: :cascade }, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.date :due_on, null: false
      t.bigint :balance_at_most_cents
      t.integer :balance_at_most_percent
      t.integer :position, null: false, default: 0
      t.text :note
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }

      t.timestamps
    end

    add_index :accounting_person_milestones, %i[ rule_id person_id ]
  end
end
