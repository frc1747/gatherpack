class CreateNoticePreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :notice_preferences, id: :uuid do |t|
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :key, null: false
      t.string :delivery, null: false

      t.timestamps
    end

    add_index :notice_preferences, %i[person_id key], unique: true
  end
end
