module Checklists
  # When an active checklist's scheduled reminders go: every N days from the
  # last scheduled one (the first as soon as the schedule is on), and N days
  # before it ends, within its dates. Days are in the site's time zone, at
  # most one scheduled reminder a day.
  class ReminderSchedule
    attr_reader :checklist

    def self.today
      Time.current.in_time_zone(Checklists.time_zone).to_date
    end

    # The checklists whose reminder is due on the day.
    def self.due(on: today)
      Checklist.active.where(reminders_scheduled: true).includes(:team).select { |checklist| new(checklist).due?(on) }
    end

    def initialize(checklist)
      @checklist = checklist
    end

    def on?
      checklist.reminders_scheduled? && (every.positive? || before_end.positive?)
    end

    def due?(on = self.class.today)
      return false unless on? && checklist.active? && within?(on)
      return false if last_on && last_on >= on

      before_end_on == on || (every.positive? && (last_on.nil? || on >= last_on + every))
    end

    # The next day a reminder is due, from the day on; nil when none will be.
    def next_on(from = self.class.today)
      return unless on? && checklist.active?

      day = from
      day += 1 if last_on && last_on >= day
      candidates = []
      candidates << [ day, last_on ? last_on + every : day ].max if every.positive?
      candidates << before_end_on if before_end_on && before_end_on >= day
      found = candidates.compact.min
      found if found && within?(found)
    end

    # The day of the last scheduled reminder.
    def last_on
      return @last_on if defined?(@last_on)

      @last_on = checklist.checklist_reminders.scheduled.maximum(:sent_at)&.in_time_zone(Checklists.time_zone)&.to_date
    end

    private

    def every
      checklist.reminder_every_days.to_i
    end

    def before_end
      checklist.reminder_days_before_end.to_i
    end

    def before_end_on
      checklist.ends_on - before_end if checklist.ends_on && before_end.positive?
    end

    def within?(day)
      starts = checklist.starts_on
      (starts.nil? || day >= starts) && (checklist.ends_on.nil? || day <= checklist.ends_on)
    end
  end
end
