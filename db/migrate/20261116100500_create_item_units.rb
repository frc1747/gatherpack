# One piece of a tracked item (inventory spec §3.15). location_id is where
# the unit physically is; a unit installed in another unit also has
# installed_in_id, and takes the outer unit's location when it moves.
class CreateItemUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :item_units, id: :uuid do |t|
      t.references :item, null: false, foreign_key: true, type: :uuid
      t.string :code
      t.string :serial_number
      t.string :name
      t.references :location, null: false, foreign_key: true, type: :uuid
      t.references :installed_in, foreign_key: { to_table: :item_units }, type: :uuid
      t.string :condition, null: false, default: "new"
      t.text :condition_note
      t.date :in_service_on
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :item_units, :code
  end
end
