# Actions on one line follow its request's policy.
class OrderLinePolicy < ApplicationPolicy
  def index?
    request_policy.show?
  end

  def show?
    request_policy.show?
  end

  # Adding an item: whoever may edit the request's items now.
  def create?
    update?
  end

  # Before approval: the requester, approvers deciding it, managers.
  def update?
    request_policy.update? || request_policy.approver_edit?
  end

  # Backorder, change quantity, split, cancel, resolve a problem.
  def buy?
    request_policy.buy?
  end

  def receive?
    request_policy.receive?
  end

  # Received without a delivery record.
  def mark_received?
    buy?
  end

  # Moving a bought line to another funding source.
  def reallocate?
    Orders::Access.for(person).funding_manager_for?(record.order_request.team_id)
  end

  private

  def request_policy
    @request_policy ||= OrderRequestPolicy.new(user, record.order_request)
  end
end
