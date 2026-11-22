# Sends the day's scheduled checklist reminders, once a day
# (config/recurring.d/checklist_reminders.yml). Every checklist due that
# day goes in one sender, so each person gets at most one checklist
# reminder email a day. Does nothing while reminders are off.
class ChecklistReminderJob < ApplicationJob
  queue_as :default

  def perform
    return unless ChecklistReminder.enabled?

    due = Checklists::ReminderSchedule.due
    return if due.empty?

    requests = due.map { |checklist| Checklists::ReminderSender::Request.new(checklist: checklist, guardians: checklist.reminder_guardians?) }
    Checklists::ReminderSender.new(requests, scheduled: true).send!
  end
end
