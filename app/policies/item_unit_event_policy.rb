# A unit's history: seen with the unit; undone per
# ItemUnitEvent#undoable_by?; never edited or deleted.
class ItemUnitEventPolicy < ApplicationPolicy
  def show?
    ItemUnitPolicy.new(user, record.item_unit).show?
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
end
