class PersonFieldBadgeGrant < ApplicationRecord
  has_neat_id :pfbg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :person_field
  belongs_to :badge
  enum :access, { read: 0, write: 1 }, validate: true

  validates :badge_id, uniqueness: { scope: :person_field_id }
  validate :badge_is_admin_assigned

  # Whether the grant counts at all: see BadgeAccessGrants.
  def effective?
    badge.grant_effective?
  end

  # A team-scoped badge only reaches people in that team or below it.
  # PersonFieldAccess checks effective? as well.
  def covers?(subject_team_ids)
    badge.team_id.nil? || subject_team_ids.include?(badge.team_id)
  end

  # Goes by team_id: a badge whose team was deleted covers nobody, not
  # everyone.
  def covered_people
    return Person.none unless effective?
    return Person.all if badge.team_id.nil?

    badge.team ? badge.team.descendant_people : Person.none
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
