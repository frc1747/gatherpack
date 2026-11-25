class CreateAccountingReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_reminders, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :accounting_rules, on_delete: :cascade }, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipient, type: :uuid, null: false, foreign_key: { to_table: :people, on_delete: :cascade }, index: false
      t.string :milestone_key, null: false
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :accounting_reminders, %i[ rule_id person_id recipient_id milestone_key ], name: "index_accounting_reminders_on_rule_person_recipient_milestone"
    add_index :accounting_reminders, %i[ recipient_id sent_at ]
  end
end
