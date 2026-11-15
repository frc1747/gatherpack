# Stock changes. History is seen with the item (and its place); recording
# follows Inventory::Access#may_record? (inventory_member_kinds for members,
# every kind for managers); undo follows StockMovement#undoable_by?.
# Movements are never edited or deleted, by anyone.
class StockMovementPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if person.nil?

      access = Inventory::Access.for(person)
      return scope.all if access.admin?

      teams = access.visible_team_ids.to_a
      scope.where(item_id: Item.where(team_id: teams).select(:id), location_id: Location.where(team_id: teams).select(:id))
    end
  end

  # Changes: every movement within reach, for managers.
  def index?
    person.present? && access.manager?
  end

  def show?
    person.present? && access.sees?(record.item) && access.sees?(record.location)
  end

  # For a new movement with kind, item and location (and to_location for a
  # move) set: may this person record it.
  def create?
    person.present? && access.may_record?(record.kind, record.item, record.location, record.try(:to_location))
  end

  def undo?
    record.undoable_by?(person)
  end

  def update?
    false
  end

  def destroy?
    false
  end

  private

  def access
    Inventory::Access.for(person)
  end
end
