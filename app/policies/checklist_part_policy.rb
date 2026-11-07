# Items, rules, grants, organizers and recorded lists belong to their
# checklist: its organizers manage them.
class ChecklistPartPolicy < ApplicationPolicy
  def show?
    checklist.organizer?(person)
  end

  def create?
    checklist.organizer?(person)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def preview?
    create?
  end

  private

  def checklist
    record.checklist
  end
end
