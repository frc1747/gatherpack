class CreateAccountingBillingLines < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_billing_lines, id: :uuid do |t|
      t.references :run, type: :uuid, null: false, foreign_key: { to_table: :accounting_billing_runs, on_delete: :cascade }, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :customer_external_id
      t.bigint :amount_cents, null: false
      t.string :status, null: false, default: "pending"
      t.uuid :request_id, null: false
      t.string :external_id
      t.text :error
      t.datetime :sent_at

      t.timestamps
    end

    add_index :accounting_billing_lines, %i[ run_id person_id ], unique: true
    add_index :accounting_billing_lines, :request_id, unique: true
    add_index :accounting_billing_lines, %i[ run_id status ]
  end
end
