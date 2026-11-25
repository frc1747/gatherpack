# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Every action is refused unless the record's policy allows it, so a policy
  # that forgets a method stays closed instead of opening up.
  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def person
    user.person
  end

  private

  # Whether the user's person manages this particular record, as opposed to
  # Person#manager?, which only says they manage some team. Admins get no
  # special case here, so call sites keep `user.admin? || manages?(...)`.
  def manages?(record)
    return false if user&.person.nil? || record.nil?

    case record
    when Team
      person.all_managed_teams.include?(record)
    when Person
      manages_person?(record)
    else
      record.respond_to?(:team) && manages?(record.team)
    end
  end

  # A manager manages the people on the teams they manage (descendants
  # included), but never an admin or architect, and never someone who manages
  # a team outside the manager's reach, such as the leader of a parent team.
  def manages_person?(other)
    managed_team_ids = person.all_managed_teams.ids
    return false unless other.memberships.exists?(team_id: managed_team_ids)
    return false if other.admin? || other.architect?

    other.memberships.where(manager: true).where.not(team_id: managed_team_ids).none?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def person
      user.person
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
