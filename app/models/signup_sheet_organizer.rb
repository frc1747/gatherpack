# A person who runs one sheet. The sheet's creator is its first organizer;
# others must hold a badge from the signups_organizers setting that reaches
# the sheet's team.
class SignupSheetOrganizer < ApplicationRecord
  has_neat_id :suor
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_sheet
  belongs_to :person

  validates :person_id, uniqueness: { scope: :signup_sheet_id, message: "is already an organizer" }
  validate :holds_grant, on: :create

  def identifier_name
    "#{signup_sheet&.title}: #{person&.display_name}"
  end

  private

  def holds_grant
    return if signup_sheet.nil? || person.nil?
    return if signup_sheet.created_by_id == person_id || signup_sheet.organizer_candidate?(person)

    errors.add(:person, "must hold an organizer badge that reaches #{signup_sheet.team.name}")
  end
end
