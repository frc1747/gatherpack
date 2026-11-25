class PagePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    # The pages #show? lets this user open, and no others: the index prints
    # the start of each page and searches their content. Team#manager? counts
    # the managers of the team and of the teams above it, which are the teams
    # all_managed_teams returns for a manager. Team and manager pages without
    # a team are for admins only.
    def resolve
      return scope.where(viewer: "public") unless user.present?
      return scope.all if user.admin

      scope.where(viewer: %w[ public user ])
        .or(scope.where(viewer: "team", team: person.all_teams))
        .or(scope.where(viewer: "manager", team: person.all_managed_teams))
    end
  end

  def show?
    return record.viewer == "public" unless user.present?
    return true if user.admin
    case record.viewer
    when "public"
      true
    when "user"
      user.present?
    when "team"
      record.team ? person.all_teams.include?(record.team) : user.admin
    when "manager"
      record.team ? record.team.manager?(person) : user.admin
    when "admin"
      user.admin
    else
      user.admin
    end
  end

  def new?
    user.present? && (user.admin? || person.manager? || person.all_teams.present?)
  end

  def update?
    return false unless user.present?
    return true if user.admin
    case record.editor
    when "user"
      user.present?
    when "team"
      record.team ? person.all_teams.include?(record.team) : user.admin
    when "manager"
      record.team ? record.team.manager?(person) : user.admin
    when "admin"
      user.admin
    else
      user.admin
    end
  end

  def create?
    update?
  end

  def destroy?
    update?
  end
end
