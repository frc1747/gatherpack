# Inventory as a whole (authorize :inventory, :reorder?): who may use it at
# all, and the manager pages (Reorder, Items, Places, Changes, labels and
# import). Records have their own policies.
class InventoryPolicy < ApplicationPolicy
  def use?
    person.present? && access.user?
  end

  def manage?
    person.present? && access.manager?
  end

  def reorder?
    manage?
  end

  def changes?
    manage?
  end

  def labels?
    manage?
  end

  def import?
    manage?
  end

  private

  def access
    Inventory::Access.for(person)
  end
end
