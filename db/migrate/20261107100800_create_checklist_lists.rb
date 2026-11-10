class CreateChecklistLists < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_lists, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: true, type: :uuid
      t.datetime :recorded_at, null: false
      t.references :recorded_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
      t.string :note
      t.jsonb :rows, null: false, default: []
      t.jsonb :configuration, null: false, default: {}
      t.timestamps
    end
  end
end
