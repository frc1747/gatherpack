class CreateSignupSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_slots, id: :uuid do |t|
      t.references :signup_position, type: :uuid, null: false, foreign_key: true, index: false
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.integer :capacity
      t.boolean :disabled, null: false, default: false

      t.timestamps
    end
    add_index :signup_slots, [ :signup_position_id, :event_id ], unique: true
  end
end
