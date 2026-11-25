module Checklists
  # A checklist's reminder settings: what its reminders may say
  # (email_level, Checklists::EmailLevel) and its schedule. Included into
  # Checklist from config/initializers/checklist_reminders.rb.
  module ReminderSettings
    extend ActiveSupport::Concern

    included do
      has_many :checklist_reminders, dependent: :delete_all

      validates :email_level, inclusion: { in: Checklists::EmailLevel::LEVELS }
      validates :reminder_every_days, :reminder_days_before_end, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
      validate :reminder_schedule_has_a_day
    end

    # The last reminder sent, by hand or on the schedule.
    def last_reminder
      checklist_reminders.order(sent_at: :desc).first
    end

    private

    def reminder_schedule_has_a_day
      return unless reminders_scheduled? && reminder_every_days.nil? && reminder_days_before_end.nil?

      errors.add(:base, "Say how often reminders go, or how many days before the end")
    end
  end

  # An item's own email level: blank (the same as the checklist) or a level.
  module ItemEmailLevel
    extend ActiveSupport::Concern

    included do
      validates :email_level, inclusion: { in: Checklists::EmailLevel::LEVELS }, allow_blank: true
      before_validation { self.email_level = email_level.presence }
    end
  end
end
