# A cache of the sum of each item's movements at each location, written in
# the same transaction as every movement. The movements are the record;
# rake inventory:rebuild_stock_levels rebuilds this from them.
class CreateStockLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_levels, id: :uuid do |t|
      t.references :item, null: false, foreign_key: true, type: :uuid, index: false
      t.references :location, null: false, foreign_key: true, type: :uuid
      t.integer :quantity, null: false, default: 0

      t.timestamps
    end
    add_index :stock_levels, %i[item_id location_id], unique: true
  end
end
