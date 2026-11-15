# Funding sources (spec §3.13). Anyone signed in may see a source's name;
# its numbers and restricted fields (giver, reference, documents, report
# due) are for funding managers, approvers and admins. Funding managers
# (orders_funding_managers, plus admins and team managers) create and edit
# sources for teams within reach.
class FundingSourcePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      person.present? ? scope.all : scope.none
    end
  end

  def index?
    person.present?
  end

  def show?
    person.present?
  end

  def create?
    person.present? && access.funding_manager?
  end

  def update?
    person.present? && access.funding_manager_for?(record.team_id)
  end

  def destroy?
    update?
  end

  # The amount, spent, committed and remaining, and the report page.
  def numbers?
    restricted_fields?
  end

  def restricted_fields?
    return false if person.nil?

    access.funding_manager_for?(record.team_id) || access.approver?
  end

  def reallocate?
    update?
  end

  private

  def access
    @access ||= Orders::Access.for(person)
  end
end
