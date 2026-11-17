# Items are seen by everyone who may use inventory and is in person.all_team_ids
# of the item's team (spec §3.6), and managed (created, edited, tracked) by
# inventory managers, team managers and admins within reach. Inactive items
# are seen only by those who manage them.
class ItemPolicy < ApplicationPolicy
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

    record.is_a?(Item) && record.team_id ? access.manages?(record.team_id) : access.manager?
  end

  def update?
    person.present? && access.manages?(record.team_id)
  end

  # Items with history can't be deleted (make them inactive instead).
  def destroy?
    update? && !record.stock_movements.exists? && !record.item_units.exists?
  end

  def start_tracking?
    update? && !record.tracked?
  end

  def stop_tracking?
    update? && record.tracked? && !record.item_units.exists?
  end

  private

  def access
    Inventory::Access.for(person)
  end
end
