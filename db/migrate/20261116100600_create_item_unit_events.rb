# A unit's history: one row per action, written in the same transaction as
# the change. Rows are only ever inserted. via_unit_id names the outer unit
# when an inner unit moved with it; reverses_id marks an undo; confirmed
# records the answer to "install anyway?" for a unit needing repair.
# Deleting a person keeps the history and blanks who did it. An event is
# reversed at most once (unique reverses_id).
class CreateItemUnitEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :item_unit_events, id: :uuid do |t|
      t.references :item_unit, null: false, foreign_key: true, type: :uuid, index: false
      t.string :action, null: false
      t.references :from_location, foreign_key: { to_table: :locations }, type: :uuid
      t.references :to_location, foreign_key: { to_table: :locations }, type: :uuid
      t.references :from_unit, foreign_key: { to_table: :item_units }, type: :uuid
      t.references :to_unit, foreign_key: { to_table: :item_units }, type: :uuid
      t.references :via_unit, foreign_key: { to_table: :item_units }, type: :uuid
      t.string :condition_before
      t.string :condition_after
      t.jsonb :readings, null: false, default: {}
      t.boolean :confirmed, null: false, default: false
      t.references :person, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :recorded_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
      t.references :reverses, foreign_key: { to_table: :item_unit_events }, type: :uuid, index: { unique: true }
      t.text :note
      t.datetime :created_at, null: false
    end
    add_index :item_unit_events, %i[item_unit_id created_at]
    add_index :item_unit_events, %i[action created_at]
  end
end
