class CreatePersonFieldValues < ActiveRecord::Migration[8.1]
  def change
    create_table :person_field_values, id: :uuid do |t|
      t.references :person, type: :uuid, null: false, foreign_key: true
      t.references :person_field, type: :uuid, null: false, foreign_key: true
      t.text :value
      t.references :updated_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }

      t.timestamps
    end
    add_index :person_field_values, [ :person_id, :person_field_id ], unique: true
  end
end
