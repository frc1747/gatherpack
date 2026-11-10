class AddReminderMessagesToForms < ActiveRecord::Migration[8.1]
  def change
    # The messages Remind last sent: one to people reminded about their own
    # response, one to guardians. Null uses the built-in default.
    add_column :forms, :reminder_message, :text
    add_column :forms, :guardian_reminder_message, :text
    # How many of a reminder's recipients were guardians, and whether the
    # sender included guardians who didn't have to act. Null on reminders
    # sent before the choice existed.
    add_column :form_reminders, :guardian_count, :integer
    add_column :form_reminders, :guardians_included, :boolean
  end
end
