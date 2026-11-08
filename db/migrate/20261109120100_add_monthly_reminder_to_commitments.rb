class AddMonthlyReminderToCommitments < ActiveRecord::Migration[8.1]
  def change
    add_column :commitments, :monthly_reminder, :boolean, null: false, default: false
    add_column :commitments, :monthly_reminded_on, :date
  end
end
