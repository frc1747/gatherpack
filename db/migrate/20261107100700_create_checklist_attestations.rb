class CreateChecklistAttestations < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_attestations, id: :uuid do |t|
      t.references :person, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :key, null: false
      t.string :statement, null: false
      t.datetime :attested_at, null: false
      t.references :attested_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
      t.timestamps
    end
    add_index :checklist_attestations, %i[person_id key attested_at]
  end
end
