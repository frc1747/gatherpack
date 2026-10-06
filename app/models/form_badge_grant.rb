# Lets holders of a badge see (read) or also fill in (respond) a form's
# responses, as if they were a leader of the people it covers. As with person
# field grants, only badges admins assign can grant access, and a team badge
# only covers people in that team or below it.
class FormBadgeGrant < ApplicationRecord
  has_neat_id :frmbg
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form
  belongs_to :badge
  enum :access, { read: 0, respond: 1 }, validate: true

  validates :badge_id, uniqueness: { scope: :form_id }
  validate :badge_is_admin_assigned

  def covers?(subject_team_ids)
    badge.team_id.nil? || subject_team_ids.include?(badge.team_id)
  end

  def covered_people
    badge.team ? badge.team.descendant_people : Person.all
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
