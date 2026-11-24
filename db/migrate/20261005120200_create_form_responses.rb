class CreateFormResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :form_responses, id: :uuid do |t|
      t.references :form, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :subject, type: :uuid, null: false, foreign_key: { to_table: :people, on_delete: :cascade }
      t.uuid :active_submission_id
      t.integer :status, null: false, default: 0
      t.boolean :update_in_progress, null: false, default: false
      t.datetime :last_reminded_at

      t.timestamps
    end
    add_index :form_responses, [ :form_id, :subject_id ], unique: true
    add_index :form_responses, :active_submission_id
  end
end
