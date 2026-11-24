# A buyer's old choice for the "ready to buy" notices, from the retired
# Buying notices page. Nothing reads it now: a person's Orders choice is
# Orders::Config.delivery_for, and the migration that retired the page copied
# these rows into Summaries' notice_preferences where that table exists. The
# table stays until it's dropped.
class OrderNoticePreference < ApplicationRecord
  belongs_to :person

  enum :buyer_notices, { digest: 0, immediate: 1, off: 2 }, prefix: :buyer

  # The person's saved preference, or an unsaved one with the defaults.
  def self.for(person)
    find_by(person_id: person.id) || new(person: person)
  end
end
