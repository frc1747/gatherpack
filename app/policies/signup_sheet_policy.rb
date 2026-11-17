class SignupSheetPolicy < ApplicationPolicy
  # Sheets the person runs, and the open and closed sheets they (or someone
  # they can sign up) are in the audience of.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.admin
      return scope.none if person.nil?

      # Must agree with SignupSheet#organizer?.
      listed = SignupSheetOrganizer.where(person_id: person.id).select(:signup_sheet_id)
      run = scope.where(id: listed, team_id: SignupSheet.creatable_team_ids(person))
        .or(scope.where(team_id: person.all_managed_teams.select(:id)))
      offered = scope.where(status: %i[ open closed ]).where.not(id: run.select(:id)).includes(:team, :signup_audience_rules)
        .select { |sheet| sheet.takers_for(person).exists? }
      run.or(scope.where(id: offered.map(&:id)))
    end
  end

  def index?
    person.present?
  end

  # Organizers see every sheet they run; others see open and closed sheets
  # they can sign up on.
  def show?
    organizer? || ((record.open? || record.closed?) && record.takers_for(person).exists?)
  end

  # Admins, team managers and organizer badge holders, for a team in reach
  # (the team isn't known yet for #new).
  def new?
    SignupSheet.creatable_team_ids(person).any?
  end

  def create?
    team_in_reach?(record.team_id)
  end

  # Settings, positions, events, organizers, slots and the roster.
  def update?
    organizer?
  end

  def manage?
    organizer?
  end

  def roster?
    organizer?
  end

  # Sheets with sign-ups are archived instead.
  def destroy?
    organizer? && !record.signups.exists?
  end

  # Whether this person may put a sheet under the team.
  def team_in_reach?(team_id)
    team_id.present? && SignupSheet.creatable_team_ids(person).include?(team_id)
  end

  private

  def organizer?
    record.organizer?(person)
  end
end
