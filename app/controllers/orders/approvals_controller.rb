module Orders
  class ApprovalsController < BaseController
    # GET /orders/approvals
    # To approve: the requests waiting on a step the viewer can decide, and
    # those with items needing re-approval, from Orders::WaitingOn.
    def index
      authorize OrderApproval
      waiting = Orders::WaitingOn.for(current_user.person)
      rows = waiting.to_approve + waiting.to_reapprove
      visible = policy_scope(OrderRequest).where(id: rows.map(&:id)).ids.to_set
      @order_requests = rows.select { |order_request| visible.include?(order_request.id) }
      ActiveRecord::Associations::Preloader.new(records: @order_requests, associations: [ :requested_by, { order_lines: :vendor } ]).call
    end
  end
end
