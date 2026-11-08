class CreatePersonFieldBadgeGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :person_field_badge_grants, id: :uuid do |t|
      t.references :person_field, type: :uuid, null: false, foreign_key: true
      t.references :badge, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :access, default: 0, null: false

      t.timestamps
    end
    add_index :person_field_badge_grants, [ :person_field_id, :badge_id ], unique: true
  end
end
