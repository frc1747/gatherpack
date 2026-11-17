# Where to buy an item: seen with the item, managed by those who manage it.
class ItemSourcePolicy < ApplicationPolicy
  def show?
    ItemPolicy.new(user, record.item).show?
  end

  def create?
    ItemPolicy.new(user, record.item).update?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
