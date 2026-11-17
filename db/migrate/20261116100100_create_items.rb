# Kinds of things kept (inventory spec §3.1, §3.15). Quantities are whole
# numbers in the item's stock unit.
class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items, id: :uuid do |t|
      t.references :team, null: false, foreign_key: true, type: :uuid, index: false
      t.string :name, null: false
      t.text :description
      t.string :category
      t.string :manufacturer
      t.string :manufacturer_part_number
      t.string :unit, null: false, default: "each"
      t.boolean :tracked, null: false, default: false
      t.jsonb :reading_fields, null: false, default: []
      t.references :home_location, foreign_key: { to_table: :locations }, type: :uuid
      t.integer :reorder_point
      t.integer :reorder_quantity
      t.string :url
      t.text :note
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :items, %i[team_id active]
    add_index :items, :manufacturer_part_number
  end
end
