class CreateOrderLines < ActiveRecord::Migration[8.1]
  def change
    create_table :order_lines, id: :uuid do |t|
      t.references :order_request, null: false, foreign_key: true, type: :uuid
      t.integer :position, null: false, default: 0
      t.text :description
      t.string :manufacturer
      t.string :manufacturer_part_number
      t.references :vendor, foreign_key: true, type: :uuid
      t.string :other_vendor_name
      t.string :other_vendor_reason
      t.string :vendor_part_number
      t.string :url
      t.integer :quantity, null: false, default: 1
      t.string :unit
      t.integer :units_per
      t.integer :estimated_unit_price_cents
      t.integer :actual_unit_price_cents
      t.integer :status, null: false, default: 0
      t.references :purchase, foreign_key: true, type: :uuid
      t.references :funding_source, foreign_key: true, type: :uuid
      t.date :expected_on
      t.references :item, polymorphic: true, type: :uuid
      t.text :note

      t.timestamps
    end
    add_index :order_lines, :status
  end
end
