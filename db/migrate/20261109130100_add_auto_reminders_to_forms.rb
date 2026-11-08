class AddAutoRemindersToForms < ActiveRecord::Migration[8.1]
  def change
    # Days before the deadline to remind people who haven't answered; 0 means
    # none, as on a sign-up sheet. Existing forms stay at 0. A new form starts
    # at 3 (FormAutoReminders). Stamped when the automatic reminder goes out.
    add_column :forms, :auto_reminder_days, :integer, default: 0, null: false
    add_column :forms, :auto_reminded_at, :datetime
  end
end
