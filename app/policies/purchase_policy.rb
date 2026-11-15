# Purchases are visible to buyers, admins, and anyone who can see one of
# their requests. Those who see it only through a request get the vendor,
# date and status, and their own lines (#visible_lines), not the rest.
class PurchasePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if person.nil?

      access = Orders::Access.for(person)
      return scope.all if access.admin?

      visible_requests = OrderRequestPolicy::Scope.new(user, OrderRequest).resolve
      scope.where(buyer_id: person.id)
        .or(scope.where(id: OrderLine.where(order_request_id: visible_requests.select(:id)).select(:purchase_id)))
    end
  end

  def index?
    person.present?
  end

  def show?
    return false if person.nil?

    full? || record.order_requests.any? { |order_request| OrderRequestPolicy.new(user, order_request).show? }
  end

  # Recording a purchase: anyone with a To buy list.
  def create?
    person.present? && Orders::Access.for(person).buyer?
  end

  # Order number, tracking, receipts, prices and shipping: its buyer, and
  # buyers or managers reaching all of its requests' teams.
  def update?
    full?
  end

  def destroy?
    false
  end

  # Sees the whole purchase, not only their own lines.
  def full?
    return false if person.nil?

    access = Orders::Access.for(person)
    access.admin? || record.buyer_id == person.id ||
      record.order_requests.all? { |order_request| access.buyer_for?(order_request.team_id) || access.manages?(order_request.team_id) }
  end

  # The lines this viewer may see.
  def visible_lines
    return record.order_lines.to_a if full?

    record.order_lines.select { |line| OrderRequestPolicy.new(user, line.order_request).show? }
  end

  def receipts?
    full?
  end

  # Record in ledger later (spec §6): the purchase isn't in a ledger yet,
  # and the viewer sees all of it and may add entries to some ledger.
  def record_in_ledger?
    record.ledger_entry_id.nil? && full? && Orders::LedgerRecording.ledgers_for(person).any?
  end

  def mark_all_received?
    show?
  end
end
