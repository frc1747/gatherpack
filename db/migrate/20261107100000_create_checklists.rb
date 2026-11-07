class CreateChecklists < ActiveRecord::Migration[8.1]
  def change
    create_table :checklists, id: :uuid do |t|
      t.references :team, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      # The window. starts_on is a fixed date; starts_within_amount and
      # starts_within_unit ("days", "months") make it "within the last N"
      # instead. A blank ends_on means "now".
      t.date :starts_on
      t.integer :starts_within_amount
      t.string :starts_within_unit
      t.date :ends_on
      t.date :cutoff_on
      t.integer :status, null: false, default: 0
      t.string :read_level, null: false, default: "family"
      t.string :met_word
      t.string :pending_word
      t.string :not_met_word
      t.datetime :next_refresh_at
      t.datetime :computed_at
      t.references :created_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
      t.timestamps
    end
    add_index :checklists, %i[status next_refresh_at]
  end
end
