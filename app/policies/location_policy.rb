# Places, as items (spec §3.6): seen by those who may use inventory and are
# in person.all_team_ids of the place's team, managed within reach.
class LocationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if person.nil?

      access = Inventory::Access.for(person)
      return scope.all if access.admin?

      scope.where(team_id: access.visible_team_ids.to_a)
        .where(active: true).or(scope.where(team_id: access.managed_team_ids.to_a))
    end
  end

  def index?
    person.present? && access.user?
  end

  def show?
    return false if person.nil?

    access.sees?(record) && (record.active? || access.manages?(record.team_id))
  end

  def create?
    return false if person.nil?

    team_id = record.is_a?(Location) ? (record.team_id || record.parent&.team_id) : nil
    team_id ? access.manages?(team_id) : access.manager?
  end

  def update?
    person.present? && access.manages?(record.team_id)
  end

  # A place with history or places inside it can't be deleted (make it
  # inactive instead).
  def destroy?
    update? && !record.stock_movements.exists? && !record.item_units.exists? && !record.children.exists?
  end

  def labels?
    show? && access.manager?
  end

  private

  def access
    Inventory::Access.for(person)
  end
end
