class FormPolicy < ApplicationPolicy
  # Everyone has "My forms".
  def index?
    true
  end

  # The status page and results: people who manage the form, and anyone who
  # can read responses beyond their own and their wards' (a teammates read
  # level, for example).
  def show?
    manage? || record.readable_subjects_for(person).where.not(id: own_subject_ids).exists?
  end

  def results?
    show?
  end

  def tally?
    show?
  end

  # The order sheet page picks its form itself, among those the viewer can
  # show.
  def order_sheet?
    true
  end

  def new?
    user.admin || person.all_managed_teams.exists? || Form.creator?(person)
  end

  # Team managers create forms for their teams. Form creators (the creator
  # badge) create event forms for teams they belong to.
  def create?
    return true if team_manager?
    Form.creator?(person) && record.event.present? && member_team_ids.include?(record.team_id)
  end

  def update?
    manage?
  end

  def destroy?
    (user.admin || creator_only?) && !record.form_submissions.where.not(submitted_at: nil).exists?
  end

  %i[ open? close? archive? duplicate? remind? preview? publish? audience? ].each { |action| alias_method action, :update? }

  # Completion badges and badge grants widen access or status: admins only.
  def manage_badges?
    user.admin
  end

  # Admins, managers of the form's team or a team above it, and the form's
  # creator while they hold the creator badge.
  def manage?
    team_manager? || record.run_by_creator?(person)
  end

  # Runs this form only as its creator: limited to event forms, with no
  # signatures or questions linked to profile fields.
  def creator_only?
    !team_manager? && record.run_by_creator?(person)
  end

  # Teams a form can belong to, for the settings form.
  def assignable_teams
    return Team.all if user.admin
    return person.all_managed_teams unless Form.creator?(person)
    Team.where(id: person.all_managed_teams.ids + member_team_ids)
  end

  private

  def team_manager?
    user.admin || (record.respond_to?(:team_id) && record.team_id.present? && person.all_managed_teams.where(id: record.team_id).exists?)
  end

  # The teams someone belongs to: their own and the teams above them.
  def member_team_ids
    @member_team_ids ||= person.all_ancestor_teams.ids
  end

  def own_subject_ids
    [ person.id ] + person.wards.ids
  end

  class Scope < ApplicationPolicy::Scope
    # The forms the user manages, and those they run as their creator.
    def resolve
      return scope.all if user.admin

      managed = scope.where(team_id: person.all_managed_teams.select(:id))
      Form.creator?(person) ? managed.or(scope.where(created_by_id: person.id)) : managed
    end
  end
end
