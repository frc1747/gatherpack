# Deletes sign-ups whose email was never confirmed, intake_entry_days after
# they started, and forgets the network prefix of entries older than 30
# days. Runs from config/recurring.yml.
class Intake::EntryExpiryJob < ApplicationJob
  queue_as :default

  IP_PREFIX_DAYS = 30

  def perform
    Intake::Entry.expired.where(person_id: nil).find_each do |entry|
      Intake.fire("intake_entries - expired", entry)
      entry.destroy!
    end
    Intake::Entry.where(created_at: ...IP_PREFIX_DAYS.days.ago).where.not(created_ip_prefix: nil).update_all(created_ip_prefix: nil)
  end
end
