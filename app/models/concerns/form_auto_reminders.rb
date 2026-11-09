# A form can remind the people who haven't answered a set number of days
# before its deadline (FormAutoReminderJob). Included into Form by
# config/initializers/forms_auto_reminders.rb.
module FormAutoReminders
  extend ActiveSupport::Concern

  DEFAULT_DAYS = 3

  included do
    # New forms start at the default while automatic reminders are on, so a
    # leader sees the setting before it applies. Otherwise (and for forms that
    # existed before, through the column default) it's 0, so turning the flag
    # on sends nothing for a form nobody set.
    attribute :auto_reminder_days, :integer, default: -> { GatherPack::Features.enabled?(:forms_auto_reminders) ? DEFAULT_DAYS : 0 }
    validates :auto_reminder_days, numericality: { only_integer: true, in: 0..60 }
    before_save :rearm_auto_reminder, if: :will_save_change_to_closes_at?

    # Open forms inside their reminder window that haven't had their
    # automatic reminder and whose deadline is still ahead.
    scope :due_for_auto_reminder, -> {
      open.where("auto_reminder_days > 0 AND auto_reminded_at IS NULL AND closes_at > :now AND closes_at - (auto_reminder_days * INTERVAL '1 day') <= :now", now: Time.current)
    }
  end

  # When the automatic reminder goes out, or nil when none is waiting. A
  # draft's is when it would go out once the form is open.
  def auto_reminder_at
    return unless (open? || draft?) && auto_reminder_days.positive? && closes_at&.future? && auto_reminded_at.nil?
    at = closes_at - auto_reminder_days.days
    open? ? [ at, Time.current ].max : at
  end

  # Stamps the reminder as sent under a row lock, so two runs can't both
  # send. True for the one run that got it.
  def claim_auto_reminder!
    with_lock do
      next false unless open? && auto_reminded_at.nil? && auto_reminder_days.positive? && closes_at&.future?
      update_columns(auto_reminded_at: Time.current)
      true
    end
  end

  private

  # A later deadline, or one set on a copy or after being cleared, gets its
  # own reminder.
  def rearm_auto_reminder
    self.auto_reminded_at = nil if closes_at && (closes_at_in_database.nil? || closes_at > closes_at_in_database)
  end
end
