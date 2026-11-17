# Units of tracked items: seen with their item, edited (code, serial, name,
# photo) by those who manage it. Each action follows
# Inventory::Access#may_unit_action? (inventory_member_unit_actions for
# members, every action for managers). While Inventory setup turns machines
# off, Install only puts a unit inside another one, so it needs another
# unit to go into (ItemUnit#install! refuses a machine then). Units aren't
# deleted: retire them.
class ItemUnitPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if person.nil?

      access = Inventory::Access.for(person)
      return scope.all if access.admin?

      scope.where(item_id: Item.where(team_id: access.visible_team_ids.to_a).select(:id))
    end
  end

  def index?
    person.present? && access.user?
  end

  def show?
    person.present? && access.sees?(record.item) && access.sees?(record.location)
  end

  def create?
    person.present? && record.item.present? && access.manages?(record.item.team_id)
  end

  def update?
    create?
  end

  def destroy?
    false
  end

  Inventory::Config::UNIT_ACTIONS.each do |action|
    define_method(:"#{action}?") { person.present? && access.may_unit_action?(action, record) }
  end

  def install?
    person.present? && (Inventory.machines? || part_to_go_into?) && access.may_unit_action?("install", record)
  end

  private

  # Another active unit this person sees, not retired and not inside this
  # one, that this unit could go inside.
  def part_to_go_into?
    excluded = [ record.id ] + record.all_contents.map(&:id)
    Scope.new(user, ItemUnit).resolve.active.not_retired.where.not(id: excluded).exists?
  end

  def access
    Inventory::Access.for(person)
  end
end
