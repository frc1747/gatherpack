# A log of each reminder send for a checklist: counts only, never the email.
class CreateChecklistReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_reminders, id: :uuid do |t|
      t.references :checklist, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :sent_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }
      t.datetime :sent_at, null: false
      t.integer :recipient_count, default: 0, null: false
      t.integer :guardian_count, default: 0, null: false
      t.boolean :scheduled, default: false, null: false

      t.timestamps
    end
    add_index :checklist_reminders, %i[checklist_id sent_at]
  end
end
