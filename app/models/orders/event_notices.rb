# Sends the notices in spec §3.11 as the request changes, from the
# timeline entries the domain actions write (included into
# OrderRequestEvent by config/initializers/orders_notices.rb) and from the
# request reaching received. The notices themselves are OrderNotices.
#
# They go out after the change is committed, so a notice never describes
# something that was rolled back, and one that fails to send is reported
# and doesn't undo the change.
module Orders
  module EventNotices
    extend ActiveSupport::Concern

    included do
      after_create_commit :send_order_notices
    end

    # The status change that has no timeline entry of its own. Subscribed
    # once from config/initializers/orders_notices.rb (a subscription isn't
    # undone by a code reload, so it looks this up each time it runs). The
    # person who received the last item isn't told.
    def self.request_changed(payload)
      return unless payload[:to] == "received" && Orders.enabled?

      order_request = payload[:order_request]
      actor = order_request.events.where(action: "received").reorder(:created_at, :id).last&.actor
      Rails.error.handle(context: { notice: "received" }) { OrderNotices.new.received(order_request, by: actor) }
    end

    private

    def send_order_notices
      return unless Orders.enabled?

      Rails.error.handle(context: { notice: action, order_request_id: order_request_id }) { notify }
    end

    def notify
      request = OrderRequest.find(order_request_id)
      notices = OrderNotices.new
      case action
      when "submitted" then notices.submitted(request, by: actor)
      when "approved" then notify_approved(request, notices)
      when "changes_requested" then notices.changes_requested(request, comment: comment, by: actor)
      when "declined" then notices.declined(request, comment: comment, by: actor, reapproval: reapproval?)
      when "purchased" then notify_purchased(request, notices)
      when "backordered" then notices.backordered(order_line, by: actor)
      when "problem" then notices.problem(order_line, by: actor)
      when "reapproval_needed" then notices.needs_reapproval(request, by: actor)
      end
    end

    # A decision on lines a buyer's change put back, rather than on the
    # request, isn't a step or a final approval: only the requester hears.
    def reapproval?
      field_changes.key?("lines")
    end

    def notify_approved(request, notices)
      return notices.approved(request, by: actor, reapproval: true) if reapproval?

      if field_changes.dig("status", 1) == "approved"
        notices.approved(request, by: actor)
      else
        notices.step_approved(request, by: actor)
      end
    end

    # A purchase writes an entry for each line, so only the first of a
    # request's lines on the same purchase speaks for all of them.
    def notify_purchased(request, notices)
      purchase = order_line&.purchase
      return if purchase.nil?

      siblings = OrderRequestEvent.where(order_request_id: order_request_id, action: "purchased",
        order_line_id: request.order_lines.where(purchase_id: purchase.id).select(:id))
      return unless siblings.order(:created_at, :id).first == self

      notices.ordered(request, purchase, by: actor)
    end
  end
end
