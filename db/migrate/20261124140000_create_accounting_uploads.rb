class CreateAccountingUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_uploads, id: :uuid do |t|
      t.references :gateway, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.string :filename
      t.text :content, null: false
      t.jsonb :parsed_records, null: false, default: {}
      t.jsonb :row_errors, null: false, default: []
      t.integer :row_count, null: false, default: 0
      t.string :status, null: false, default: "previewed"
      t.references :applied_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.datetime :applied_at

      t.timestamps
    end
  end
end
