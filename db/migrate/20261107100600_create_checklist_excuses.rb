class CreateChecklistExcuses < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_excuses, id: :uuid do |t|
      t.references :item, null: false, foreign_key: { to_table: :checklist_items }, type: :uuid
      t.references :person, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # One meeting, for kinds that count events; null excuses the whole item.
      t.references :event, foreign_key: { on_delete: :cascade }, type: :uuid
      t.text :reason, null: false
      t.date :expires_on
      t.references :created_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
      t.timestamps
    end
  end
end
