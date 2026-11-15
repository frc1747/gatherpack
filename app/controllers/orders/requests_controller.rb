module Orders
  class RequestsController < BaseController
    # GET /orders/requests
    # The requests the viewer can see; mine=1 limits them to their own and
    # those they follow.
    def index
      authorize OrderRequest
      @order_requests = policy_scope(OrderRequest).includes(:team, :order_lines).order(updated_at: :desc)
      if params[:mine].present?
        person = current_user.person
        @order_requests = @order_requests.where(requested_by: person)
          .or(@order_requests.where(id: OrderRequestWatcher.where(person: person).select(:order_request_id)))
      end
      @order_requests = @order_requests.page(params[:page])
    end

    # GET /orders/requests/new
    def new
      @order_request = authorize OrderRequest.new(requested_by: current_user.person, team: current_user.person&.teams&.first)
    end

    # GET /orders/requests/1
    def show
      @order_request = authorize policy_scope(OrderRequest)
        .includes(:team, :requested_by, :order_approvals, :order_request_watchers, order_lines: %i[vendor purchase])
        .find(params[:id])
    end
  end
end
