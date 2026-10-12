# Reminds the people on a sign-up its sheet's reminder_days before the
# event. Scheduled when the sign-up is made or moved and when the event's
# time changes; a reminder whose sign-up has since been cancelled, moved,
# or whose event has moved does nothing, since the change scheduled a new one.
class SignupReminderJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  # Schedules the reminder, unless the sheet sends none (reminder_days 0)
  # or it's already too late for it.
  def self.schedule_for(signup)
    days = signup.signup_sheet.reminder_days
    event = signup.event
    return if days.zero? || !signup.active?

    at = event.start_time - days.days
    set(wait_until: at).perform_later(signup, event.id, event.start_time.iso8601) if at > Time.current
  end

  def perform(signup, event_id, start_time)
    return unless GatherPack::Features.enabled?(:signups)

    event = signup.event
    return unless signup.active? && event.id == event_id && event.start_time.to_i == Time.iso8601(start_time).to_i
    return if signup.signup_sheet.archived? || signup.signup_sheet.reminder_days.zero? || event.start_time <= Time.current

    SignupNotices.new.reminder(signup)
  end
end
