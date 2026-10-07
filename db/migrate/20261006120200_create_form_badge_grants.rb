class CreateFormBadgeGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :form_badge_grants, id: :uuid do |t|
      t.references :form, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :badge, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :access, null: false, default: 0

      t.timestamps
    end
    add_index :form_badge_grants, [ :form_id, :badge_id ], unique: true
  end
end
