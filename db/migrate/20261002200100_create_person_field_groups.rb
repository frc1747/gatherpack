class CreatePersonFieldGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :person_field_groups, id: :uuid do |t|
      t.string :name, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end
  end
end
