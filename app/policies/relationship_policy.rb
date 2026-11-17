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

  # A minor guardianship can only be removed by a manager or admin, so a
  # child can't cut off their guardian. Either side can remove a consented
  # one, since the child side granted it.
  def destroy?
    return true if user.admin?

    participant = record.parent == person || record.child == person
    manager = person.can_manage(record.parent) || person.can_manage(record.child)
    case record.relationship_type.guardianship
    when "minor" then manager
    when "consented" then participant || manager
    else participant
    end
  end

  alias_method :reverse?, :destroy?
end
