# Places things are kept (inventory spec §3.1). Nested by parent_id; a
# location's code is unique within its top-level place, which the model
# checks because the top-level place is derived.
class CreateLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :locations, id: :uuid do |t|
      t.references :team, null: false, foreign_key: true, type: :uuid
      t.references :parent, foreign_key: { to_table: :locations }, type: :uuid
      t.string :name, null: false
      t.string :code
      t.string :kind, null: false, default: "storage"
      t.text :note
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :locations, %i[team_id active]
  end
end
