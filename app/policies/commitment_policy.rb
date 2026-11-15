class CommitmentPolicy < ApplicationPolicy
  # Commitments the person runs, those they owe, and those owed by a group
  # they're related to.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.admin
      return scope.none if person.nil?

      # Must agree with Commitment#organizer?.
      listed = CommitmentOrganizer.where(person_id: person.id).select(:commitment_id)
      run = scope.where(id: listed, team_id: Commitment.creatable_team_ids(person))
        .or(scope.where(team_id: person.all_managed_teams.select(:id)))
      owed = scope.where.not(id: run.select(:id)).includes(:owing_team).select { |commitment| commitment.covers?(person) || commitment.group_relative?(person) }
      run.or(scope.where(id: owed.map(&:id)))
    end
  end

  def index?
    person.present?
  end

  # Organizers see everyone's progress; people who owe see their own, and
  # people related to a group through its relationship type see the group's.
  def show?
    organizer? || record.covers?(person) || record.group_relative?(person)
  end

  # Admins, team managers and organizer badge holders, for a team in reach
  # (the team isn't known yet for #new).
  def new?
    Commitment.creatable_team_ids(person).any?
  end

  def create?
    team_in_reach?(record.team_id)
  end

  # Settings, sources, organizers and adjustments.
  def update?
    organizer?
  end

  def manage?
    organizer?
  end

  # Everyone's progress, and messaging people with open commitments.
  def progress?
    organizer?
  end

  def message?
    organizer?
  end

  def destroy?
    organizer?
  end

  # Whether this person may put a commitment under the team.
  def team_in_reach?(team_id)
    team_id.present? && Commitment.creatable_team_ids(person).include?(team_id)
  end

  private

  def organizer?
    record.organizer?(person)
  end
end
