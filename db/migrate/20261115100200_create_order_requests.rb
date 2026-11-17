class CreateOrderRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :order_requests, id: :uuid do |t|
      t.references :team, null: false, foreign_key: true, type: :uuid
      t.references :requested_by, null: false, foreign_key: { to_table: :people }, type: :uuid
      t.string :title
      t.text :purpose
      t.date :needed_by
      t.integer :status, null: false, default: 0
      t.references :funding_source, foreign_key: true, type: :uuid
      t.integer :estimated_shipping_cents, null: false, default: 0
      t.integer :approved_total_cents
      t.datetime :submitted_at
      t.datetime :approved_at
      t.datetime :closed_at

      t.timestamps
    end
    add_index :order_requests, :status
  end
end
