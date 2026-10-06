class CreateForms < ActiveRecord::Migration[8.1]
  def change
    create_table :forms, id: :uuid do |t|
      t.string :title, null: false
      t.string :key, null: false
      t.text :description
      t.references :team, type: :uuid, null: false, foreign_key: true
      t.references :audience_badge, type: :uuid, foreign_key: { to_table: :badges }
      t.integer :kind, null: false, default: 0
      t.integer :respond_permission, null: false, default: 5
      t.integer :read_permission, null: false, default: 5
      t.integer :status, null: false, default: 0
      t.datetime :opens_at
      t.datetime :closes_at
      t.boolean :allow_updates, null: false, default: true
      t.integer :late_entry, null: false, default: 1
      t.integer :content_version, null: false, default: 1
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }

      t.timestamps
    end
    add_index :forms, :key, unique: true
    add_index :forms, :status
  end
end
