class CreateIntakeEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :intake_entries, id: :uuid do |t|
      t.references :registration, type: :uuid, null: false, foreign_key: { to_table: :intake_registrations, on_delete: :cascade }
      t.integer :source, default: 0, null: false
      # Encrypted, so text rather than string or jsonb.
      t.text :email
      t.string :first_name
      t.string :last_name
      t.text :facts
      t.string :token_digest, index: { unique: true }
      t.datetime :expires_at
      t.datetime :verified_at
      t.references :person, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :created_ip_prefix
      t.timestamps
      t.index [ :registration_id, :verified_at ]
    end

    create_table :intake_household_members, id: :uuid do |t|
      t.references :entry, type: :uuid, null: false, foreign_key: { to_table: :intake_entries, on_delete: :cascade }
      t.references :person, type: :uuid, foreign_key: { on_delete: :nullify }
      t.integer :role, default: 0, null: false
      t.text :facts
      t.datetime :guardian_confirmed_at
      t.string :token_digest, index: { unique: true }
      t.datetime :token_expires_at
      t.timestamps
    end
  end
end
