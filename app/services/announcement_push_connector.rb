# Prepended to AnnouncementNotificationRouter from
# config/initializers/phone_notifications.rb. The emails are queued first, and
# a failure here can't stop them. Errors from the emails themselves still raise.
module AnnouncementPushConnector
  def run
    result = super
    send_push_notifications
    result
  end

  private
    def send_push_notifications
      return unless GatherPack::PushChannel.available? && @announcement.notify_now.present? && @announcement.notify_now != "0"

      path = Rails.application.routes.url_helpers.announcement_path(@announcement)
      @people.each { |person| GatherPack::PushChannel.deliver(person, topic: :announcements, title: @announcement.title, path: path) }
    rescue StandardError => e
      Rails.logger.error("Announcement phone notifications failed: #{e.class}: #{e.message}")
    end
end
