class BadgePolicy < ApplicationPolicy
  # Kinds of team badge the team's managers look after. The admin kinds stay
  # with admins.
  MANAGED_PERMISSIONS = %w[added_by_manager added_by_manager_or_self added_by_current_member has_account].freeze

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(team: person.all_teams).or(scope.where(team_id: nil))
      end
    end
  end

  # The same records Scope lists, which is how the controller loads them.
  def show?
    Scope.new(user, Badge).resolve.exists?(record.id)
  end

  def new?
     user.admin || person.all_managed_teams.present?
  end

  def create?
    user.admin || (record.team && person.all_managed_teams.include?(record.team))
  end

  # Changing or deleting a badge is for admins and, on a team badge that
  # managers may hand out, the managers of that team. Being allowed to take a
  # badge oneself doesn't make it one's own to change (BadgeAssignmentPolicy).
  def update?
    user.admin? || (record.team.present? && MANAGED_PERMISSIONS.include?(record.permission) && manages?(record.team))
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
