class PersonPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(id: (person.all_teams.map(&:all_people).flatten.map(&:id) << person.id)).distinct
      end
    end
  end

  def show?
    record == person || user.admin? || (person.all_teams & record.all_teams).any?
  end

  # The extra read-only member pages share the same visibility rule as #show.
  alias_method :recent_activity?, :show?
  alias_method :calendar?, :show?
  alias_method :statistics?, :show?
  alias_method :relationships?, :show?
  alias_method :teams?, :show?

  # Creating a person can also create their login, so it's admin-only.
  def create?
    user.admin?
  end

  # Managers edit the people they manage, so not an admin or architect, nor
  # someone who manages a team above them.
  def update?
    record == person || user.admin? || manages?(record)
  end

  def destroy?
    user.admin?
  end

  # Impersonating someone hands over their powers, so only an architect may
  # impersonate an architect.
  def impersonate?
    user.admin? && (user.architect? || !record.user&.architect?)
  end

  def stop_impersonating?
    user.admin?
  end
end
