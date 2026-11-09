class AnnouncementNotificationRouter
  def initialize(announcement)
    @announcement = announcement
    @people = announcement.team ? announcement.team.all_people : Person.all
  end

  def run
    return if @announcement.notify_now.blank? || @announcement.notify_now == "0"
    helpers = ApplicationController.helpers

    subject = "#{Settings[:title]} - #{@announcement.title}"
    content = ""
    content << "<h1>Announcement Posted in #{ERB::Util.h(@announcement&.team&.name || Settings[:title])}</h1>"
    content << "<h2>#{ERB::Util.h(@announcement.title)}</h2><div>#{helpers.md(@announcement.content)}</div>"
    @people.each do |person|
      next unless person.user
      next unless person.user.email.present?
      SendEmailJob.perform_later(Gateway[:email_sending], person.user.email, subject, content)
    end
  end
end
