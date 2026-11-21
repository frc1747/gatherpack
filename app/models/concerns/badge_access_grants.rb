# Badges that grant access to data (person fields, forms) trust that an admin
# chose who holds them. A badge grants only while that stays true: while
# it's admin-assigned and, for a team badge, while its team still exists (a
# deleted team leaves its badges behind, and a missing team must not read as
# an org-wide badge).
#
# Features register the associations that hold their grants, so a badge
# with grants can't be switched to a kind members assign themselves. Each
# feature includes the concern from its initializer (repeating the include is
# harmless, so initializer order doesn't matter) and registers:
#
#   Badge.include(BadgeAccessGrants)
#   Badge.register_access_grants(:person_field_badge_grants)
module BadgeAccessGrants
  extend ActiveSupport::Concern

  included do
    class_attribute :access_grant_associations, instance_writer: false, default: []

    validate :access_grants_need_admin_assignment

    # Badges whose grants count, as a relation usable in subqueries.
    scope :grant_effective, -> { added_by_admin.where(team_id: nil).or(added_by_admin.where(team_id: Team.select(:id))) }
  end

  class_methods do
    def register_access_grants(association)
      self.access_grant_associations = access_grant_associations | [ association.to_sym ]
    end
  end

  def grant_effective?
    return false unless added_by_admin?
    return true if team_id.nil?

    if association(:team).loaded? && (team.nil? || team.id == team_id)
      team.present?
    else
      Team.exists?(id: team_id)
    end
  end

  def access_grants?
    persisted? && access_grant_associations.any? { |name| association(name).scope.exists? }
  end

  private

  def access_grants_need_admin_assignment
    return unless will_save_change_to_permission? && permission_in_database == "added_by_admin" && !added_by_admin?

    errors.add(:permission, "Remove this badge's access grants before changing who can add it") if access_grants?
  end
end
