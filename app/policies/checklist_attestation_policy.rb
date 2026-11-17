# Who may confirm an attested item is the item's setting
# (ChecklistAttestation.may_attest?). The record carries the item it's for
# in item.
class ChecklistAttestationPolicy < ApplicationPolicy
  def create?
    record.item.present? && !record.item.checklist.archived? && ChecklistAttestation.may_attest?(record.item, person, record.person)
  end

  # The one who confirmed, or the checklist's organizers.
  def destroy?
    return false if record.item.nil? || record.item.checklist.archived?

    record.attested_by_id == person&.id || record.item.checklist.organizer?(person)
  end
end
