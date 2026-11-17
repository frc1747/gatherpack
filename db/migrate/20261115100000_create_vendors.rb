class CreateVendors < ActiveRecord::Migration[8.1]
  def change
    create_table :vendors, id: :uuid do |t|
      t.string :name, null: false
      t.string :website
      t.string :domains, array: true, null: false, default: []
      t.string :part_number_pattern
      t.text :account_note
      t.boolean :preferred, null: false, default: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :vendors, :name
  end
end
