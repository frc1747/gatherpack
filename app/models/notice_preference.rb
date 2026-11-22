# A person's own choice of how a summary section reaches them (see
# GatherPack::Digests.delivery_for). Without a row the person gets the
# site's choice.
class NoticePreference < ApplicationRecord
  DELIVERIES = %w[each daily weekly off].freeze

  belongs_to :person

  validates :key, presence: true, uniqueness: { scope: :person_id }
  validates :delivery, inclusion: { in: DELIVERIES }

  def valid_delivery?
    DELIVERIES.include?(delivery)
  end
end
