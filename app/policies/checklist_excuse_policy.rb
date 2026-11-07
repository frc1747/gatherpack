# Managers of the checklist's team and above, and admins, excuse; never
# themselves or a relative (ChecklistExcuse.allowed?).
class ChecklistExcusePolicy < ApplicationPolicy
  def create?
    ChecklistExcuse.allowed?(record.item.checklist, person, record.person)
  end

  def destroy?
    record.item.checklist.manager?(person)
  end
end
