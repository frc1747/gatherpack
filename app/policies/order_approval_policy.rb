# Decisions are made through the request (OrderRequestPolicy#decide?);
# approval rows are never edited or removed by hand.
class OrderApprovalPolicy < ApplicationPolicy
  def index?
    person.present?
  end

  def show?
    OrderRequestPolicy.new(user, record.order_request).show?
  end

  def create?
    OrderRequestPolicy.new(user, record.order_request).decide?
  end

  def update?
    false
  end

  def destroy?
    false
  end
end
