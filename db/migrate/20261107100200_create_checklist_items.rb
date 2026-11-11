class CreateChecklistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_items, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: true, type: :uuid
      t.references :parent, foreign_key: { to_table: :checklist_items }, type: :uuid
      t.string :kind, null: false
      t.jsonb :config, null: false, default: {}
      t.string :label, null: false
      t.integer :position, null: false, default: 0
      t.boolean :counts, null: false, default: true
      # Dates overriding the checklist's window, in the same shape.
      t.date :starts_on
      t.integer :starts_within_amount
      t.string :starts_within_unit
      t.date :ends_on
      t.date :due_on
      t.string :read_level
      t.string :exempt_label
      t.timestamps
    end
    add_index :checklist_items, :kind
  end
end
