# Reminds the people on a sign-up its sheet's reminder_days before the
# event. Scheduled when the sign-up is made or moved, when the event's time
# changes and when the sheet's reminder_days changes. A job sends only if
# its sign-up is still active in the same slot, the event's start is the
# one it was scheduled for, the sheet's current reminder_days makes it due,
# and no reminder has gone out yet (reminded_at), so stale or duplicate
# jobs do nothing. While the sign-ups feature is off, a job that is due
# waits an hour at a time (until the event starts) rather than being lost.
class SignupReminderJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  # Schedules the reminder, unless the sheet sends none (reminder_days 0)
  # or it's already too late for it. With fresh (a move or a time change),
  # a reminder already sent is forgotten, since the new date needs its own.
  def self.schedule_for(signup, fresh: false)
    days = signup.signup_sheet.reminder_days
    event = signup.event
    return if days.zero? || !signup.active?

    at = event.start_time - days.days
    return if at <= Time.current

    signup.update_columns(reminded_at: nil) if fresh && signup.reminded_at
    set(wait_until: at).perform_later(signup, signup.signup_slot_id, event.start_time.iso8601)
  end

  def perform(signup, slot_id, start_time)
    signup.with_lock do
      event = signup.event
      days = signup.signup_sheet.reminder_days
      return unless signup.active? && signup.reminded_at.nil? && signup.signup_slot_id == slot_id
      return unless event.start_time.to_i == Time.iso8601(start_time).to_i
      return if signup.signup_sheet.archived? || days.zero? || event.start_time <= Time.current
      # Not due yet: reminder_days has shrunk since this was scheduled, and
      # a later job is waiting.
      return if Time.current < event.start_time - days.days - 1.minute

      unless GatherPack::Features.enabled?(:signups)
        retry_at = 1.hour.from_now
        self.class.set(wait_until: retry_at).perform_later(signup, slot_id, start_time) if retry_at < event.start_time
        return
      end

      SignupNotices.new.reminder(signup)
      signup.update_columns(reminded_at: Time.current)
    end
  end
end
