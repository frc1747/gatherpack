# Emails people who still owe on the commitments whose organizers asked for a
# monthly reminder. Runs every hour (config/recurring.yml) but acts only on
# the 1st of the month from 9 AM in the site's time zone, so a worker that is
# down that day skips the month rather than making it up later. Each
# commitment is stamped before it is sent, so a retry or a second worker
# can't send twice.
class CommitmentMonthlyReminderJob < ApplicationJob
  queue_as :default

  SEND_HOUR = 9

  def perform
    return unless GatherPack::Features.enabled?(:commitments) && GatherPack::Features.enabled?(:commitment_monthly_reminders)
    return unless Gateway[:email_sending]

    Time.use_zone(Settings[:time_zone].presence || "UTC") do
      now = Time.zone.now
      return unless now.day == 1 && now.hour >= SEND_HOUR

      today = now.to_date
      due = Commitment.where(monthly_reminder: true).where("starts_on <= ? AND ends_on >= ?", today, today)
        .where("monthly_reminded_on IS NULL OR monthly_reminded_on < ?", today.beginning_of_month)
      claimed = due.select { |commitment| due.where(id: commitment.id).update_all(monthly_reminded_on: today) == 1 }
      Commitments::MonthlyReminder.new(claimed).deliver if claimed.any?
    end
  end
end
