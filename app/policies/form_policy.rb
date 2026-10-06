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

  def new?
    user.admin || person.all_managed_teams.exists?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    user.admin && !record.form_submissions.where.not(submitted_at: nil).exists?
  end

  %i[ open? close? archive? duplicate? remind? preview? ].each { |action| alias_method action, :update? }

  # Admins, and managers of the form's team or a team above it.
  def manage?
    user.admin || (record.team.present? && person.all_managed_teams.where(id: record.team_id).exists?)
  end

  # Teams a form can belong to, for the settings form.
  def assignable_teams
    user.admin ? Team.all : person.all_managed_teams
  end

  private

  def own_subject_ids
    [ person.id ] + person.wards.ids
  end

  class Scope < ApplicationPolicy::Scope
    # The forms the user manages.
    def resolve
      user.admin ? scope.all : scope.where(team_id: person.all_managed_teams.select(:id))
    end
  end
end
