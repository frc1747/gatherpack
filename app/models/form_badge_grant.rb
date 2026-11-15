# Lets holders of a badge see (read) or also fill in (respond) a form's
# responses, as if they were a leader of the people it covers. As with person
# field grants, only badges admins assign can grant access, and a team badge
# only covers people in that team or below it.
class FormBadgeGrant < ApplicationRecord
  has_neat_id :frmbg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  include FormCompletionBadgeGuard

  belongs_to :form
  belongs_to :badge
  enum :access, { read: 0, respond: 1 }, validate: true

  validates :badge_id, uniqueness: { scope: :form_id }
  validate :badge_is_admin_assigned

  # Whether the grant counts at all: only while its badge is admin-assigned
  # and its team (if any) exists. See BadgeAccessGrants.
  def effective?
    badge.grant_effective?
  end

  def covers?(subject_team_ids)
    effective? && (badge.team_id.nil? || subject_team_ids.include?(badge.team_id))
  end

  # Goes by team_id: a badge whose team was deleted covers nobody, not
  # everyone.
  def covered_people
    return Person.none unless effective?
    return Person.all if badge.team_id.nil?

    badge.team ? badge.team.descendant_people : Person.none
  end

  def identifier_name
    "#{badge&.name}: #{read? ? "can see" : "can see and fill in"} #{form&.title}"
  end

  private

  # Otherwise anyone who can assign the badge to themselves could grant
  # themselves access to the responses.
  def badge_is_admin_assigned
    errors.add(:badge, "must be one only admins can assign") if badge && !badge.added_by_admin?
  end
end
