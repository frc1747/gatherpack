# Every change to the quantity of an item at a location. Rows are only
# ever inserted: the model refuses updates and deletes, so there is no
# updated_at. Deleting a person keeps the stock record and blanks who did
# it, as upstream keeps ledger entries whose creator is gone. A movement is
# reversed at most once (unique reverses_id).
class CreateStockMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_movements, id: :uuid do |t|
      t.references :item, null: false, foreign_key: true, type: :uuid, index: false
      t.references :location, null: false, foreign_key: true, type: :uuid, index: false
      t.string :kind, null: false
      t.integer :quantity, null: false
      t.integer :counted_quantity
      t.references :person, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :recorded_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
      t.string :reason
      t.text :note
      t.uuid :move_group_id
      t.references :reverses, foreign_key: { to_table: :stock_movements }, type: :uuid, index: { unique: true }
      t.datetime :created_at, null: false
    end
    add_index :stock_movements, %i[item_id location_id created_at]
    add_index :stock_movements, %i[location_id created_at]
    add_index :stock_movements, :move_group_id
  end
end
