# A person who runs one commitment. Its creator is its first organizer;
# others must hold a badge from the commitments_organizers setting that
# reaches the commitment's team.
class CommitmentOrganizer < ApplicationRecord
  has_neat_id :cmor
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :commitment
  belongs_to :person

  validates :person_id, uniqueness: { scope: :commitment_id, message: "is already an organizer" }
  validate :holds_grant, on: :create

  def identifier_name
    "#{commitment&.title}: #{person&.display_name}"
  end

  private

  def holds_grant
    return if commitment.nil? || person.nil?
    return if commitment.created_by_id == person_id || commitment.organizer_candidate?(person)

    errors.add(:person, "must hold an organizer badge that reaches #{commitment.team.name}")
  end
end
