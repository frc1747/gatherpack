# Prepended to FormReminderSender from
# config/initializers/phone_notifications_connectors.rb. The emails are queued
# first, and a failure here can't stop them.
module FormReminderPushConnector
  def send!(...)
    result = super
    send_push_notifications
    result
  end

  private
    # One per person who was emailed. The title is only the form's, so a
    # guardian's lock screen doesn't name the child.
    def send_push_notifications
      return unless GatherPack::PushChannel.available?

      urls = Rails.application.routes.url_helpers
      title = "Reminder: #{form.title}"
      recipients.each do |recipient, recipient_subjects|
        subject = recipient_subjects.first
        path = outstanding_signers(subject).any? ? urls.form_response_path(form, subject.id) : urls.edit_form_response_path(form, subject.id)
        GatherPack::PushChannel.deliver(recipient, topic: :forms, title: title, path: path)
      end
    rescue StandardError => e
      Rails.logger.error("Form reminder phone notifications failed: #{e.class}: #{e.message}")
    end
end
