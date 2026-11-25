class CreateAccountingCustomerDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_customer_dismissals, id: :uuid do |t|
      t.references :gateway, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :customer_external_id, null: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :accounting_customer_dismissals, %i[ gateway_id customer_external_id person_id ], unique: true,
      name: "index_accounting_customer_dismissals_on_customer_and_person"
  end
end
