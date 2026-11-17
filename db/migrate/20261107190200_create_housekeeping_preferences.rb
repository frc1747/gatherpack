# Each person's saved default for a housekeeping list (H2): which view
# opens ("current", the not-archived ones, or "archived") and an optional
# "ended before" filter in the date control's config shape.
class CreateHousekeepingPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :housekeeping_preferences, id: :uuid do |t|
      t.references :person, null: false, index: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :list_key, null: false
      t.string :view, null: false, default: "current"
      t.jsonb :older
      t.timestamps
    end
    add_index :housekeeping_preferences, %i[person_id list_key], unique: true
  end
end
