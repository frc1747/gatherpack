# A manual credit (or, negative, a debit) for one person on a commitment,
# with a reason. Counts as confirmed, apart from source caps, and shows
# separately in the breakdown.
class CommitmentAdjustment < ApplicationRecord
  has_neat_id :cmad
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :commitment
  belongs_to :person
  belongs_to :created_by, class_name: "Person", optional: true

  validates :credits, numericality: { only_integer: true, other_than: 0 }
  validates :reason, presence: true
  validate :person_owes

  def identifier_name
    "#{commitment&.title}: #{person&.display_name} #{format("%+d", credits.to_i)}"
  end

  private

  def person_owes
    return if commitment.nil? || person.nil?

    errors.add(:person, "doesn't owe this commitment") unless commitment.covers?(person)
  end
end
