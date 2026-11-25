class CreateKioskDevices < ActiveRecord::Migration[8.1]
  def change
    # A computer paired to run the time kiosk without anyone signed in. The
    # device's secret and its one-time pairing code are kept only as digests.
    create_table :kiosk_devices, id: :uuid do |t|
      t.string :name, null: false
      t.string :secret_digest
      t.string :pairing_code_digest
      t.datetime :pairing_expires_at
      t.datetime :last_seen_at
      t.datetime :revoked_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :kiosk_devices, :pairing_code_digest, unique: true
  end
end
