class CreateAccountingRules < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_rules, id: :uuid do |t|
      t.references :gateway, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :key, null: false
      t.text :description
      t.string :kind, null: false
      t.jsonb :filters, null: false, default: {}
      t.jsonb :settings, null: false, default: {}
      t.text :code
      t.references :team, type: :uuid, foreign_key: { on_delete: :nullify }
      t.integer :read_permission, null: false, default: 0
      t.integer :amount_permission, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :accounting_rules, :key, unique: true
  end
end
