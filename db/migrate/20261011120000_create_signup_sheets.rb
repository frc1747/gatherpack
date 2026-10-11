class CreateSignupSheets < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_sheets, id: :uuid do |t|
      t.references :team, type: :uuid, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :contact
      t.integer :status, null: false, default: 0
      t.references :event_type, type: :uuid, foreign_key: { on_delete: :nullify }
      t.integer :names_permission, null: false, default: 0
      t.uuid :others_relationship_type_ids, array: true, null: false, default: []
      t.integer :on_behalf_of_mode, null: false, default: 0
      t.integer :cancel_cutoff_hours, null: false, default: 0
      t.integer :reminder_days, null: false, default: 2
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }

      t.timestamps
    end
    add_index :signup_sheets, :status
  end
end
