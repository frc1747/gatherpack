class CreateAccountingBillingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_billing_runs, id: :uuid do |t|
      t.references :gateway, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :rule, type: :uuid, foreign_key: { to_table: :accounting_rules, on_delete: :nullify }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.string :item_external_id, null: false
      t.bigint :amount_cents, null: false
      t.date :txn_date
      t.date :due_on
      t.text :memo
      t.boolean :create_customers, null: false, default: false
      t.boolean :send_from_source, null: false, default: false
      t.string :status, null: false, default: "draft"
      t.datetime :finished_at

      t.timestamps
    end
  end
end
