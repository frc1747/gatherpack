class CreateFormSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :form_submissions, id: :uuid do |t|
      t.references :form_response, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :number, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :answers, null: false, default: {}
      t.integer :form_version, null: false
      t.references :based_on, type: :uuid, foreign_key: { to_table: :form_submissions, on_delete: :nullify }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.references :submitted_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.datetime :submitted_at
      t.datetime :activated_at
      t.boolean :entered_late, null: false, default: false
      t.jsonb :profile_skipped, null: false, default: []

      t.timestamps
    end
    add_index :form_submissions, [ :form_response_id, :number ], unique: true
    # One active, and one draft or pending, submission per response.
    add_index :form_submissions, :form_response_id, unique: true, where: "status = 2", name: "index_form_submissions_one_active"
    add_index :form_submissions, :form_response_id, unique: true, where: "status IN (0, 1)", name: "index_form_submissions_one_open"
    add_index :form_submissions, :answers, using: :gin
    add_foreign_key :form_responses, :form_submissions, column: :active_submission_id, on_delete: :nullify
  end
end
