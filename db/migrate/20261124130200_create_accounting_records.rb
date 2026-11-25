class CreateAccountingRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_records, id: :uuid do |t|
      t.references :gateway, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :entity_type, null: false
      t.string :external_id, null: false
      t.string :revision
      t.jsonb :data, null: false, default: {}

      t.string :role, null: false
      t.string :customer_external_id
      t.string :parent_external_id
      t.string :name
      t.string :email
      t.string :reference
      t.boolean :active, null: false, default: true
      t.string :number
      t.date :txn_date
      t.date :due_on
      t.bigint :total_cents
      t.bigint :balance_cents
      t.boolean :voided, null: false, default: false
      t.jsonb :lines, null: false, default: []
      t.string :item_ids, array: true, null: false, default: []
      t.string :class_ids, array: true, null: false, default: []
      t.string :location_ids, array: true, null: false, default: []
      t.jsonb :applied_to, null: false, default: []
      t.bigint :unapplied_cents
      t.string :pay_url
      t.string :external_url
      t.string :public_label
      t.text :description
      t.datetime :external_updated_at
      t.datetime :deleted_at
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :accounting_records, %i[ gateway_id entity_type external_id ], unique: true, name: "index_accounting_records_on_source_and_external_id"
    add_index :accounting_records, :role
    add_index :accounting_records, %i[ gateway_id customer_external_id ]
    add_index :accounting_records, :txn_date
    add_index :accounting_records, :item_ids, using: :gin
    add_index :accounting_records, :class_ids, using: :gin
    add_index :accounting_records, :location_ids, using: :gin
  end
end
