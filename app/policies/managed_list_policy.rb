# Who may manage a registered managed list (GatherPack::ManagedLists): admins,
# plus anyone the list's registration policy allows. The record is the list's
# model class or one of its rows.
class ManagedListPolicy < ApplicationPolicy
  def index?
    allowed?
  end

  def show?
    allowed?
  end

  def create?
    allowed?
  end

  def update?
    allowed?
  end

  def destroy?
    allowed?
  end

  def move?
    allowed?
  end

  def retire?
    allowed?
  end

  def restore?
    allowed?
  end

  def merge?
    allowed?
  end

  private

  def allowed?
    model = record.is_a?(Class) ? record : record.class
    list = GatherPack::ManagedLists.for_model(model)
    list.present? && list.allowed?(user)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      list = GatherPack::ManagedLists.for_model(scope.all.klass)
      list&.allowed?(user) ? scope.all : scope.none
    end
  end
end
