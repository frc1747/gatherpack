class CreateIntakeRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :intake_registrations, id: :uuid do |t|
      t.references :team, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.string :slug, null: false, index: { unique: true }
      t.text :description
      t.datetime :opens_at, null: false
      t.datetime :closes_at
      t.boolean :self_service, default: true, null: false
      t.boolean :kiosk, default: false, null: false
      # Points at a checklist once checklists are installed; no foreign key here.
      t.uuid :checklist_id
      t.boolean :gate_approval, default: false, null: false
      t.boolean :pick_one_required, default: false, null: false
      t.references :guardian_relationship_type, type: :uuid, foreign_key: { to_table: :relationship_types, on_delete: :nullify }
      t.references :successor, type: :uuid, foreign_key: { to_table: :intake_registrations, on_delete: :nullify }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.timestamps
    end

    create_table :intake_registration_teams, id: :uuid do |t|
      t.references :registration, type: :uuid, null: false, foreign_key: { to_table: :intake_registrations, on_delete: :cascade }
      t.references :team, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :kind, default: 0, null: false
      t.timestamps
      t.index [ :registration_id, :team_id, :kind ], unique: true, name: "index_intake_registration_teams_unique"
    end

    create_table :intake_registration_badges, id: :uuid do |t|
      t.references :registration, type: :uuid, null: false, foreign_key: { to_table: :intake_registrations, on_delete: :cascade }
      t.references :badge, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
      t.index [ :registration_id, :badge_id ], unique: true, name: "index_intake_registration_badges_unique"
    end
  end
end
