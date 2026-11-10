# Items, rules, grants, organizers and recorded lists belong to their
# checklist: its organizers manage them, and nothing changes on an archived
# checklist (recorded lists stay readable).
class ChecklistPartPolicy < ApplicationPolicy
  def show?
    checklist.organizer?(person)
  end

  def create?
    !checklist.archived? && checklist.organizer?(person)
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
