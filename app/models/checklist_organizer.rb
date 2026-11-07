# A person who runs one checklist. Its creator is its first organizer;
# others must hold a badge from the checklists_organizers setting that
# reaches the checklist's team.
class ChecklistOrganizer < ApplicationRecord
  has_neat_id :chlo
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :checklist
  belongs_to :person

  validates :person_id, uniqueness: { scope: :checklist_id, message: "is already an organizer" }
  validate :holds_grant, on: :create

  def identifier_name
    "#{checklist&.title}: #{person&.display_name}"
  end

  private

  def holds_grant
    return if checklist.nil? || person.nil?
    return if checklist.created_by_id == person_id || checklist.manager?(person) || checklist.organizer_candidate?(person)

    errors.add(:person, "must hold an organizer badge that reaches #{checklist.team.name}")
  end
end
