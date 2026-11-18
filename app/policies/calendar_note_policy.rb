class CalendarNotePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(noteable: (person.all_teams.map(&:person_ids).flatten << person.id).uniq).or(scope.where(noteable: person.all_teams)).or(scope.where(noteable: nil))
      end
    end
  end

  # Records are loaded through Scope, which decides who may see them.
  def show?
    true
  end

  # Anyone with a person may open the form: they can at least add a note on
  # themselves. Saving checks the note they actually fill in.
  def new?
    user.admin? || person.present?
  end

  def create?
    writable?
  end

  def update?
    writable?
  end

  def edit?
    update?
  end

  def destroy?
    writable?
  end

  private

  # Team notes belong to the team's managers, person notes to the person and
  # their managers, and organisation-wide notes to admins.
  def writable?
    return true if user.admin?

    case record.noteable
    when Team
      manages?(record.noteable)
    when Person
      record.noteable == person || manages?(record.noteable)
    else
      false
    end
  end
end
