class RelationshipPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        people = (person.all_teams.map(&:person_ids).flatten << person.id).uniq
        scope.where(parent_id: people).and(scope.where(child_id: people))
          .or(scope.where(parent_id: person.id).or(scope.where(child_id: person.id)))
          .distinct
      end
    end
  end

  def new?
    true
  end

  def create?
    true
  end

  def destroy?
    # `person` is the acting user's Person; the edge connects two People, so
    # compare against those, not the User. (Previously compared a Person to a
    # User, so this was never true for a non-admin.)
    user.admin? || record.parent == person || record.child == person
  end

  # Reversing an edge changes its direction, so gate it like destroy.
  alias_method :reverse?, :destroy?
end
