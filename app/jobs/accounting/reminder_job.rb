# Daily: sends every account reminder due today (Accounting::Reminders).
# Does nothing while the feature is off.
class Accounting::ReminderJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "accounting_reminders"

  def perform
    return unless Accounting.enabled?

    Accounting::Reminders.new.send!
  end
end
