class CreateSignupSheetEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_sheet_events, id: :uuid do |t|
      t.references :signup_sheet, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.boolean :created_by_sheet, null: false, default: false

      t.timestamps
    end
    add_index :signup_sheet_events, [ :signup_sheet_id, :event_id ], unique: true
  end
end
