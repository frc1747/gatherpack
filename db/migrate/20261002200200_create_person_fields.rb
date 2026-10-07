class CreatePersonFields < ActiveRecord::Migration[8.1]
  def change
    create_table :person_fields, id: :uuid do |t|
      t.string :name, null: false
      t.string :key, null: false
      t.integer :data_type, default: 0, null: false
      t.jsonb :options, default: {}, null: false
      t.text :help_text
      t.integer :read_permission, default: 0, null: false
      t.integer :write_permission, default: 0, null: false
      t.references :team, type: :uuid, foreign_key: true
      t.references :person_field_group, type: :uuid, foreign_key: true
      t.integer :position, default: 0, null: false
      t.boolean :required, default: false, null: false
      t.boolean :show_on_profile, default: true, null: false
      t.datetime :archived_at
      t.string :system_source

      t.timestamps
    end
    add_index :person_fields, :key, unique: true
    add_index :person_fields, :system_source, unique: true
  end
end
