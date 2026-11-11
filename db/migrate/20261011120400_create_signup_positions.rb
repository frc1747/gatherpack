class CreateSignupPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_positions, id: :uuid do |t|
      t.references :signup_sheet, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.integer :kind, null: false, default: 0
      t.string :unit
      t.integer :capacity
      t.string :question
      t.boolean :question_required, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
