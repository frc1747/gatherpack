class CreateChecklistOrganizers < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_organizers, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: true, type: :uuid
      t.references :person, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.timestamps
    end
    add_index :checklist_organizers, %i[checklist_id person_id], unique: true
  end
end
