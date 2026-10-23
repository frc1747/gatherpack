class CreateSignupSheetOrganizers < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_sheet_organizers, id: :uuid do |t|
      t.references :signup_sheet, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :signup_sheet_organizers, [ :signup_sheet_id, :person_id ], unique: true
  end
end
