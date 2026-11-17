class BadgeAssignmentPolicy < ApplicationPolicy
  # Holders are listed like on the badge's page: only the people the user may
  # see. Those who manage a badge (as in BadgePolicy#update?) see all of its
  # holders, so they can still take it from someone who has left the team.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.admin?

      managed_badges = Badge.where(team: person.all_managed_teams, permission: BadgePolicy::MANAGED_PERMISSIONS)
      scope.where(person: PersonPolicy::Scope.new(user, Person).resolve).or(scope.where(badge: managed_badges))
    end
  end

  # Anyone who may see the badge sees who holds it. The record is the badge
  # when listing.
  def index?
    BadgePolicy.new(user, badge).show?
  end

  def show?
    index? && Scope.new(user, BadgeAssignment).resolve.exists?(record.id)
  end

  # Whether there is anyone the user may give this badge to, themselves
  # included.
  def new?
    gives_badge_to?(person)
  end

  def create?
    gives_badge_to?(record.person)
  end

  # Checked with the current holder and again with the new one assigned.
  def update?
    gives_badge_to?(record.person)
  end

  def edit?
    update?
  end

  def destroy?
    gives_badge_to?(record.person)
  end

  private

  def badge
    record.is_a?(Badge) ? record : record.badge
  end

  # Who may give this badge to holder, or take it away again. Those who may
  # manage the badge give it to anyone the badge allows (the model checks that
  # a team badge's holder is on its team); otherwise it depends on the kind.
  def gives_badge_to?(holder)
    return false if holder.nil? || badge.nil?
    return true if BadgePolicy.new(user, badge).update?

    case badge.permission
    when "added_by_admin"
      false # admins only
    when "added_by_manager"
      false # admins and the managers of the badge's team only
    when "added_by_admin_or_self"
      holder == person # anyone, for themselves
    when "added_by_manager_or_self"
      holder == person || (badge.team.nil? && manages?(holder)) # anyone for themselves; without a team, managers also for the people they manage
    when "has_account"
      holder == person # anyone signed in, for themselves
    when "added_by_current_member"
      holder == person && person.all_teams.include?(badge.team) # members of the badge's team, for themselves
    else
      false
    end
  end
end
