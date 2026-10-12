module Signups
  # Included into Event from config/initializers/signups.rb, so event.rb
  # stays as upstream has it. When an event's date or time changes (often an
  # event entered as 00:00 to 23:59 getting its real time), everyone signed
  # up for it is told, their reminders move with it, and its sheets announce
  # the change.
  module EventChanges
    extend ActiveSupport::Concern

    included do
      after_update_commit :tell_signups_about_time_change, if: -> { saved_change_to_start_time? || saved_change_to_end_time? }
    end

    private

    def tell_signups_about_time_change
      return unless GatherPack::Features.enabled?(:signups)

      SignupNotices.new.event_changed(self,
        start_time_was: saved_changes.fetch("start_time", [ start_time ]).first,
        end_time_was: saved_changes.fetch("end_time", [ end_time ]).first)
      Signup.active.joins(:signup_slot).where(signup_slots: { event_id: id }).find_each { |signup| SignupReminderJob.schedule_for(signup) }
      signup_sheet_events.each { |sheet_event| Signups.sheet_changed(sheet_event.signup_sheet_id, self, :event_time) }
    end
  end
end
