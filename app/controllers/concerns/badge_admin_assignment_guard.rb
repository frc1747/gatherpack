# Person field grants (and other features) trust an "added_by_admin" badge to
# mean an admin chose its holders. Keeps non-admins from making such a badge,
# handing one out, or putting a badge on a team they don't manage. Included
# into BadgesController from the person-fields initializer.
module BadgeAdminAssignmentGuard
  extend ActiveSupport::Concern

  included do
    before_action :guard_badge_admin_assignment, only: %i[ create update ]
  end

  private

  def guard_badge_admin_assignment
    return if current_user.admin?

    raise Pundit::NotAuthorizedError, "only admins make or hand out admin-assigned badges" if badge_admin_assignment_refused?
  end

  # Decides from what the action will apply (badge_params, over the current
  # badge or a new one's defaults), not from the raw request.
  def badge_admin_assignment_refused?
    permitted = badge_params
    current = action_name == "update" ? @badge : nil
    candidate = Badge.new(current ? { permission: current.permission, team_id: current.team_id } : {})
    candidate.assign_attributes(permitted.slice(:permission, :team_id))

    if candidate.added_by_admin?
      return true if current.nil? || !current.added_by_admin?
      return true if permitted.key?(:person_ids)
    end

    candidate.team_id != current&.team_id && !current_user.person.all_managed_teams.exists?(id: candidate.team_id)
  rescue ActionController::ParameterMissing
    false # The action raises the same error itself.
  end
end
