# Who sees and runs checklists. The list shows checklists someone runs
# (as a manager of its team, or an organizer who still holds a badge that
# reaches it), and those with results they may see: their own, their wards',
# the people they lead, or through a grant. Drafts and archived checklists
# are only for the people who run them, and archived ones are read-only.
# Which rows and columns someone sees inside is Checklists::Visibility's
# job.
class ChecklistPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.admin?
      return scope.none if person.nil?

      run = scope.where(team_id: Checklists.team_subtree_ids(Membership.where(person_id: person.id, manager: true).pluck(:team_id)))
        .or(scope.where(id: ChecklistOrganizer.where(person_id: person.id).select(:checklist_id), team_id: Checklist.creatable_team_ids(person)))
      seen = [ person.id ] + person.wards.ids
      results = ChecklistResult.where(item_id: nil)
      shown = scope.where(id: results.where(person_id: seen).select(:checklist_id))
        .or(scope.where(id: results.where(person_id: person.all_managed_people.select(:id)).select(:checklist_id)))
        .or(scope.where(id: granted_ids))
      run.or(shown.where.not(status: :draft))
    end

    private

    def granted_ids
      badge_ids = BadgeAssignment.where(person_id: person.id).select(:badge_id)
      team_ids = Checklists.team_ancestor_ids(person.memberships.pluck(:team_id))
      ChecklistGrant.where(badge_id: badge_ids).or(ChecklistGrant.where(team_id: team_ids)).select(:checklist_id)
    end
  end

  def index?
    true
  end

  def show?
    Scope.new(user, Checklist).resolve.exists?(id: record.id)
  end

  def new?
    Checklist.creatable_team_ids(person).any?
  end

  def create?
    record.team_id.present? && Checklist.creatable_team_ids(person).include?(record.team_id)
  end

  # Archived checklists are read-only until restored.
  def update?
    !record.archived? && record.organizer?(person)
  end

  def destroy?
    record.organizer?(person)
  end

  def restore?
    record.archived? && record.organizer?(person)
  end

  # Copying an archived checklist (last year's) is how next year starts.
  def copy?
    record.organizer?(person)
  end

  alias_method :copy_form?, :copy?
  alias_method :preview?, :update?
  alias_method :refresh?, :update?
end
