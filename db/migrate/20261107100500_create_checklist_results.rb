class CreateChecklistResults < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_results, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: true, type: :uuid, index: false
      # Null for the checklist's overall result.
      t.references :item, foreign_key: { to_table: :checklist_items, on_delete: :cascade }, type: :uuid
      t.references :person, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.integer :status, null: false
      t.string :label
      t.string :summary
      t.text :detail
      t.jsonb :measures, null: false, default: {}
      t.jsonb :fix
      t.jsonb :excuse
      t.integer :previous_status
      t.datetime :changed_at
      t.datetime :computed_at, null: false
      t.boolean :stale, null: false, default: false
      t.timestamps
    end
    add_index :checklist_results, %i[checklist_id item_id person_id], unique: true, nulls_not_distinct: true,
      name: "index_checklist_results_on_checklist_item_person"
    add_index :checklist_results, %i[checklist_id item_id status], name: "index_checklist_results_on_checklist_item_status"
  end
end
