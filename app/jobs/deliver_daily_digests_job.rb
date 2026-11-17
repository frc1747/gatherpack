# Sends each person one email with the summary sections set to go out daily
# (GatherPack::Digests). Scheduled every few minutes in
# config/recurring.d/digests.yml and sends once SEND_HOUR has passed in the
# site's time zone (Settings time_zone), so a server clock in another zone or
# a run missed at that minute doesn't matter.
# DigestDelivery keeps it to one email per person per day.
class DeliverDailyDigestsJob < ApplicationJob
  queue_as :default

  SEND_HOUR = 7

  # Today's send time in the site's time zone.
  def self.due_at(now = Time.current)
    zone = ActiveSupport::TimeZone[Settings[:time_zone].presence || "UTC"] || ActiveSupport::TimeZone["UTC"]
    now.in_time_zone(zone).change(hour: SEND_HOUR)
  end

  def perform(now = Time.current)
    return unless GatherPack::Digests.enabled?
    return if GatherPack::Digests.entries.none?(&:daily?)

    due_at = self.class.due_at(now)
    return if now < due_at

    today = due_at.to_date
    since = due_at - 1.day
    sent = DigestDelivery.where(delivered_on: today).pluck(:person_id)
    gateway = Gateway[:email_sending]
    subject = "Your #{Settings[:title]} update"

    Person.joins(:user).includes(:user).where.not(id: sent).find_each do |person|
      next if person.user.email.blank?

      content = GatherPack::Digests.daily_content(person, since: since, on: today)
      next unless DigestDelivery.claim(person, today)
      next unless content

      SendEmailJob.perform_later(gateway, person.user.email, subject, content)
      DigestDelivery.where(person: person, delivered_on: today).update_all(sent: true, updated_at: Time.current)
    end

    DigestDelivery.prune(today)
  end
end
