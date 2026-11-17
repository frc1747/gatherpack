class CreateDigestDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :digest_deliveries, id: :uuid do |t|
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :delivered_on, null: false
      t.boolean :sent, null: false, default: false

      t.timestamps
    end

    add_index :digest_deliveries, %i[person_id delivered_on], unique: true
    add_index :digest_deliveries, :delivered_on
  end
end
