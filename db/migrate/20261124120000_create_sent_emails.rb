class CreateSentEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :sent_emails, id: :uuid do |t|
      t.references :gateway, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :person, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :about, type: :uuid, polymorphic: true
      t.string :address, null: false
      t.string :subject
      t.string :job_id
      t.string :provider_message_id
      t.string :status, null: false, default: "sending"
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :problem_at
      t.text :problem_detail
      t.datetime :first_clicked_at
      t.integer :click_count, null: false, default: 0
      t.text :first_clicked_url
      t.datetime :opened_at

      t.timestamps
    end

    add_index :sent_emails, :job_id, unique: true
    add_index :sent_emails, [ :gateway_id, :provider_message_id ], unique: true
    add_index :sent_emails, :created_at
  end
end
