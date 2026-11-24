class CreateFormQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :form_questions, id: :uuid do |t|
      t.references :form, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0
      t.integer :kind, null: false, default: 0
      t.string :label
      t.text :body
      t.string :key, null: false
      t.integer :data_type, null: false, default: 0
      t.jsonb :options, null: false, default: {}
      t.references :person_field, type: :uuid, foreign_key: true
      t.integer :profile_mode
      t.boolean :required, null: false, default: false
      t.integer :read_permission
      t.integer :write_permission

      t.timestamps
    end
    add_index :form_questions, [ :form_id, :key ], unique: true
  end
end
