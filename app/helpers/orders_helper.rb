# Screen words for orders (spec §3.16): the model keeps its names, the
# screens use plain ones.
module OrdersHelper
  REQUEST_STATUS_WORDS = {
    "draft" => "Draft",
    "submitted" => "Waiting for approval",
    "changes_requested" => "Needs changes",
    "approved" => "Approved, not ordered yet",
    "ordering" => "Ordered",
    "received" => "Here",
    "closed" => "Closed",
    "declined" => "Declined",
    "cancelled" => "Cancelled"
  }.freeze

  LINE_STATUS_WORDS = {
    "pending" => "Waiting for approval",
    "approved" => "Approved, not ordered yet",
    "ordered" => "Ordered",
    "backordered" => "Delayed",
    "partly_received" => "Partly here",
    "received" => "Here",
    "problem" => "Problem with delivery",
    "cancelled" => "Cancelled",
    "needs_reapproval" => "Needs re-approval"
  }.freeze

  # Request statuses in which a pending item isn't waiting for approval.
  UNDECIDED_LINE_REQUEST_STATUSES = %w[changes_requested declined cancelled].freeze

  # The request's status as lists show it: "Ordered: 2 of 3 here", plus
  # "1 needs re-approval" when a buyer's change is waiting.
  def order_request_status_text(order_request)
    text = REQUEST_STATUS_WORDS.fetch(order_request.status, order_request.status.humanize)
    if order_request.ordering?
      lines = order_request.live_lines
      text += ": #{lines.count(&:received?)} of #{lines.size} here"
    end
    waiting = order_request.reapproval_lines.size
    text += ", #{waiting} #{waiting == 1 ? 'needs' : 'need'} re-approval" if waiting.positive? && !order_request.finished?
    text
  end

  # Items nobody decided on take the request's outcome: once a request is
  # declined, an item isn't waiting for approval any more.
  def order_line_status_text(line)
    request_status = line.order_request.status
    return REQUEST_STATUS_WORDS.fetch(request_status) if line.pending? && request_status.in?(UNDECIDED_LINE_REQUEST_STATUSES)

    LINE_STATUS_WORDS.fetch(line.status, line.status.humanize)
  end

  # Renders orders/requests/_<slot> when another part of orders has added
  # it, so the request page grows without editing its template.
  def order_request_slot(slot, **locals)
    return unless lookup_context.exists?(slot.to_s, [ "orders/requests" ], true)

    render "orders/requests/#{slot}", **locals
  end
end
