class CreateChecklistGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_grants, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: true, type: :uuid
      t.references :badge, foreign_key: true, type: :uuid
      t.references :team, foreign_key: true, type: :uuid
      t.uuid :item_ids, array: true, null: false, default: []
      t.integer :access, null: false, default: 0
      t.timestamps
    end
  end
end
