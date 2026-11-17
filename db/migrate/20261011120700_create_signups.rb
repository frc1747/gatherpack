class CreateSignups < ActiveRecord::Migration[8.1]
  def change
    create_table :signups, id: :uuid do |t|
      t.references :signup_slot, type: :uuid, null: false, foreign_key: true, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :signed_up_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.references :on_behalf_of, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.integer :extra_people, null: false, default: 0
      t.text :extra_names
      t.integer :quantity
      t.text :answer
      t.text :note
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :signups, [ :signup_slot_id, :status ]
  end
end
