# A person's choice for the "ready to buy" notices (spec §3.11): a daily
# digest of what's waiting, an email for each request as it's approved, or
# none. Without a row, everyone who can buy gets the digest.
class OrderNoticePreference < ApplicationRecord
  belongs_to :person

  enum :buyer_notices, { digest: 0, immediate: 1, off: 2 }, prefix: :buyer

  # The person's saved preference, or an unsaved one with the defaults.
  def self.for(person)
    find_by(person_id: person.id) || new(person: person)
  end
end
