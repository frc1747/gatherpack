class CreateOrderDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :order_deliveries, id: :uuid do |t|
      t.references :order_line, null: false, foreign_key: true, type: :uuid
      t.integer :quantity, null: false
      t.references :received_by, null: false, foreign_key: { to_table: :people }, type: :uuid
      t.date :received_on, null: false
      t.integer :condition, null: false, default: 0
      t.text :note

      t.timestamps
    end
  end
end
