class CreateMenuPins < ActiveRecord::Migration[8.1]
  def change
    create_table :menu_pins, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :path_key, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :menu_pins, %i[user_id path_key], unique: true
  end
end
