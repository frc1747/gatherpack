class CreateChecklistRefreshes < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_refreshes, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      # Null marks the whole checklist.
      t.uuid :person_id
      t.datetime :created_at, null: false
    end
    add_index :checklist_refreshes, %i[checklist_id person_id], unique: true, nulls_not_distinct: true
  end
end
