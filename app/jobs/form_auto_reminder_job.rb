# Emails the people who haven't answered an open form a set number of days
# before its deadline (Form#auto_reminder_days), once per deadline. Sends
# the same message a leader's Remind does. Does nothing while forms or
# automatic reminders are off, or with no email gateway.
class FormAutoReminderJob < ApplicationJob
  queue_as :default

  def perform
    return unless GatherPack::Features.enabled?(:forms) && GatherPack::Features.enabled?(:forms_auto_reminders)
    return unless Gateway[:email_sending]

    Form.due_for_auto_reminder.find_each do |form|
      next unless form.claim_auto_reminder!

      # Guardians who would only be nudging are emailed from the second
      # reminder on, as on the Remind screen.
      sender = FormReminderSender.new(form, FormPending.new(form).people, include_guardians: form.form_reminders.exists?)
      sender.send!(sent_by: nil, filter: { automatic: true }) if sender.recipients.any?
    end
  end
end
