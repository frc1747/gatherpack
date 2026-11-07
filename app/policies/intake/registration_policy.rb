# Registrations are run by their team's managers (managers of an ancestor
# team included) and admins.
class Intake::RegistrationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin
      return scope.none unless person
      scope.where(team_id: person.all_managed_teams.select(:id))
    end
  end

  def index?
    user&.admin || person&.manager? || false
  end

  def show?
    manages?
  end

  def new?
    index?
  end

  def create?
    manages?
  end

  def update?
    manages?
  end

  def destroy?
    manages?
  end

  def copy?
    manages?
  end

  def close?
    manages?
  end

  def destroy_entries?
    manages?
  end

  def resend?
    manages?
  end

  private

  def manages?
    return false unless user && record.respond_to?(:team)
    return true if user.admin
    return false unless person && record.team
    person.all_managed_teams.exists?(id: record.team_id)
  end
end
