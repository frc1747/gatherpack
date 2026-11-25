module Checklists
  # Follows each reminder email with a phone notification built from the
  # same message, so it follows the same email levels: a checklist whose
  # reminders say only "sign in" isn't named, and a guardian's lock screen
  # doesn't name the ward. Prepended to Checklists::ReminderSender from
  # config/initializers/checklist_reminders.rb only where the phone
  # notifications seam (GatherPack::PushChannel) exists. The email is queued
  # first, and a failure here can't stop it.
  module ReminderPushConnector
    TOPIC = :checklists

    private

    def deliver(message)
      result = super
      send_push_notification(message)
      result
    end

    def send_push_notification(message)
      return unless GatherPack::PushChannel.available?

      GatherPack::PushChannel.deliver(message.recipient, topic: TOPIC, title: message.push_title, path: message.push_path)
    rescue StandardError => e
      Rails.logger.error("Checklist reminder phone notifications failed: #{e.class}: #{e.message}")
    end
  end
end
