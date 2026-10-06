class AddConsentColumnsToForms < ActiveRecord::Migration[8.1]
  def change
    add_reference :forms, :completion_badge, type: :uuid, foreign_key: { to_table: :badges, on_delete: :nullify }
    add_column :forms, :reconfirm_on_profile_change, :boolean, null: false, default: false
    # content_version is the version of what respondents see now. Changing an
    # answered form starts a new one; Publish changes accepts it
    # (published_version) and may ask earlier responses to re-confirm
    # (reconfirm_from_version).
    add_column :forms, :published_version, :integer, null: false, default: 1
    add_column :forms, :reconfirm_from_version, :integer, null: false, default: 1

    add_column :form_questions, :signer, :integer

    # What the respondent saw when they submitted: the form's text and
    # questions. Signatures cover it along with the answers.
    add_column :form_submissions, :content, :jsonb, null: false, default: {}
  end
end
