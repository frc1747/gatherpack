class CreateCommitments < ActiveRecord::Migration[8.1]
  def change
    create_table :commitments, id: :uuid do |t|
      t.references :team, type: :uuid, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.references :owing_team, type: :uuid, null: false, foreign_key: { to_table: :teams }
      t.references :owing_badge, type: :uuid, foreign_key: { to_table: :badges }
      t.integer :base_amount, null: false, default: 1
      t.string :unit, null: false, default: ""
      t.integer :counts_when, null: false, default: 0
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }

      t.timestamps
    end
  end
end
