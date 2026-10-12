class CreateFormReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :form_reminders, id: :uuid do |t|
      t.references :form, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :sent_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.datetime :sent_at, null: false
      t.integer :recipient_count, null: false, default: 0
      t.jsonb :filter, null: false, default: {}

      t.timestamps
    end
  end
end
