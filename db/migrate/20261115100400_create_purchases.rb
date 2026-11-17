class CreatePurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :purchases, id: :uuid do |t|
      t.references :vendor, foreign_key: true, type: :uuid
      t.string :other_vendor_name
      t.references :buyer, null: false, foreign_key: { to_table: :people }, type: :uuid
      t.string :vendor_order_number
      t.date :ordered_on
      t.integer :shipping_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.string :paid_with
      t.references :reimburse_to, foreign_key: { to_table: :people }, type: :uuid
      t.string :tracking_url
      t.date :expected_on
      t.references :ledger_entry, foreign_key: true, type: :uuid
      t.text :note

      t.timestamps
    end
  end
end
