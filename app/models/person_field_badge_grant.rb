class PersonFieldBadgeGrant < ApplicationRecord
  has_neat_id :pfbg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :person_field
  belongs_to :badge
  enum :access, { read: 0, write: 1 }, validate: true

  validates :badge_id, uniqueness: { scope: :person_field_id }
  validate :badge_is_admin_assigned

  # A team-scoped badge only reaches people in that team or below it.
  def covers?(subject_team_ids)
    badge.team_id.nil? || subject_team_ids.include?(badge.team_id)
  end

  def covered_people
    badge.team ? badge.team.descendant_people : Person.all
  end

  def identifier_name
    "#{badge&.name}: #{read? ? "can see" : "can see and edit"} #{person_field&.name}"
  end

  private

  # Otherwise anyone who can assign the badge to themselves could grant
  # themselves access to the field.
  def badge_is_admin_assigned
    errors.add(:badge, "must be one only admins can assign") if badge && !badge.added_by_admin?
  end
end
