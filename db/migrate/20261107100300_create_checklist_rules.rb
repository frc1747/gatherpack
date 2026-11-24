class CreateChecklistRules < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_rules, id: :uuid do |t|
      t.references :checklist, null: false, foreign_key: true, type: :uuid
      t.references :item, foreign_key: { to_table: :checklist_items }, type: :uuid
      t.integer :effect, null: false, default: 0
      t.integer :target_type, null: false, default: 0
      t.references :team, foreign_key: true, type: :uuid
      t.references :badge, foreign_key: true, type: :uuid
      t.references :person, foreign_key: { on_delete: :cascade }, type: :uuid
      t.boolean :include_managers, null: false, default: true
      t.timestamps
    end
  end
end
