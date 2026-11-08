class CreateFormSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :form_signatures, id: :uuid do |t|
      t.references :form_submission, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :form_question, type: :uuid, null: false, foreign_key: true
      t.references :signer, type: :uuid, null: false, foreign_key: { to_table: :people }
      t.integer :signer_role, null: false
      t.string :typed_name, null: false
      t.datetime :signed_at, null: false
      t.string :content_digest, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :revoked_at
      t.references :revoked_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.string :revoked_reason

      t.timestamps
    end
    # One standing signature per signature question per submission.
    add_index :form_signatures, [ :form_submission_id, :form_question_id ], unique: true, where: "revoked_at IS NULL",
      name: "index_form_signatures_one_standing"
  end
end
