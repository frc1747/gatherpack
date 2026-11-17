# Where an item can be bought. Free-text vendor names: inventory works
# without orders.
class CreateItemSources < ActiveRecord::Migration[8.1]
  def change
    create_table :item_sources, id: :uuid do |t|
      t.references :item, null: false, foreign_key: true, type: :uuid
      t.string :vendor_name, null: false
      t.string :vendor_part_number
      t.string :url
      t.boolean :preferred, null: false, default: false
      t.text :note
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
