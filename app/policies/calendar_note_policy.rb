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

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    true
  end
end
