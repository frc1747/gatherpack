# Prepended to AnnouncementNotificationRouter from
# config/initializers/phone_notifications.rb. The emails are queued first, and
# nothing here can stop them.
module AnnouncementPushConnector
  def run
    result = super
    send_push_notifications if GatherPack::PushChannel.available? && @announcement.notify_now.present? && @announcement.notify_now != "0"
    result
  rescue StandardError => e
    Rails.logger.error("Announcement phone notifications failed: #{e.class}: #{e.message}")
    result
  end

  private
    def send_push_notifications
      path = Rails.application.routes.url_helpers.announcement_path(@announcement)
      @people.each { |person| GatherPack::PushChannel.deliver(person, topic: :announcements, title: @announcement.title, path: path) }
    end
end
