class CreateWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :widgets, id: :uuid do |t|
      t.string :title
      t.boolean :show_title, default: true, null: false
      t.text :content
      t.boolean :dynamic, default: false, null: false
      t.text :stylesheet
      t.string :style_mode, default: "theme", null: false
      t.text :javascript
      t.integer :refresh_seconds, default: 0, null: false
      t.string :placement, default: "right", null: false
      t.integer :position, default: 0, null: false
      t.string :viewer, default: "user", null: false
      t.references :team, type: :uuid
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end
  end
end
