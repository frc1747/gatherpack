# Scheduled reminders, off by default: every N days to people not complete,
# optionally N days before the checklist ends, optionally to guardians too,
# and optionally through the person's summary email instead.
class AddReminderScheduleToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_column :checklists, :reminders_scheduled, :boolean, default: false, null: false
    add_column :checklists, :reminder_every_days, :integer
    add_column :checklists, :reminder_days_before_end, :integer
    add_column :checklists, :reminder_guardians, :boolean, default: false, null: false
    add_column :checklists, :reminder_via_digest, :boolean, default: false, null: false
  end
end
