# Recording a delivery follows the request's receive permission.
class OrderDeliveryPolicy < ApplicationPolicy
  def index?
    person.present?
  end

  def show?
    OrderRequestPolicy.new(user, record.order_line.order_request).show?
  end

  def create?
    OrderRequestPolicy.new(user, record.order_line.order_request).receive?
  end

  def update?
    false
  end

  def destroy?
    false
  end
end
