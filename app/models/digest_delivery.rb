# One row per person per day the daily summary was built for them, whether or
# not it had anything to send. The unique index is what keeps a person to one
# daily summary even when the job runs twice or two runs overlap.
class DigestDelivery < ApplicationRecord
  KEEP_FOR = 60.days

  belongs_to :person

  # Claims today's summary for the person. False when it was already claimed.
  def self.claim(person, on)
    transaction(requires_new: true) { create!(person: person, delivered_on: on) }
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def self.prune(today)
    where(delivered_on: ...(today - KEEP_FOR)).delete_all
  end
end
