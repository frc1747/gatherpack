# Registrations open and close by date, with no state to change, so this
# fires the opened and closed hooks for dates passed since the last run.
# Runs hourly from config/recurring.yml; the window is one hour.
class Intake::RegistrationDatesJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current, window = 1.hour)
    range = (now - window)...now
    Intake::Registration.where(opens_at: range).find_each { |registration| Intake.fire("intake_registrations - opened", registration) }
    Intake::Registration.where(closes_at: range).find_each { |registration| Intake.fire("intake_registrations - closed", registration) }
  end
end
