module Orders
  # Receiving: the To receive list, the delivery dialog and Mark all
  # received (spec §3.6).
  class DeliveriesController < BaseController
    before_action :set_line, only: %i[new create]

    # GET /orders/deliveries
    # Items to receive, by purchase; mine=1 limits them to the viewer's own
    # and followed requests.
    def index
      authorize OrderRequest
      @receiving = Orders::Receiving.new(current_user, policy_scope(OrderRequest), mine: params[:mine].present?)
    end

    # GET /orders/requests/1/lines/2/deliveries/new
    def new
      Orders::Lists.seed_delivery_problem_kinds!
      @delivery = OrderDelivery.new(order_line: @line, quantity: [ @line.to_come_quantity, 1 ].max,
        received_on: Date.current)
    end

    # POST /orders/requests/1/lines/2/deliveries
    def create
      problem_kind = chosen_problem_kind
      @delivery = OrderDelivery.new(order_line: @line, quantity: delivery_params[:quantity], received_on: delivery_params[:received_on],
        delivery_problem_kind: problem_kind, note: delivery_params[:note])
      @line.record_delivery!(by: current_user.person, quantity: delivery_params[:quantity].to_i,
        received_on: delivery_params[:received_on].presence&.to_date, problem_kind: problem_kind,
        note: delivery_params[:note].presence, photo: delivery_params[:photo].presence, params: params)
      redirect_to after_path, notice: "Recorded: #{@line.display_name}"
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      @delivery.errors.add(:base, error.message) if error.is_a?(ArgumentError)
      @delivery.errors.merge!(error.record.errors) if error.respond_to?(:record)
      render :new, status: :unprocessable_entity
    end

    # POST /orders/requests/1/mark_all_received
    def mark_all_request
      @order_request = authorize policy_scope(OrderRequest).find(params[:id]), :receive?
      @order_request.mark_all_received!(by: current_user.person)
      redirect_to after_path, notice: "Everything on this request is marked as here"
    end

    # POST /orders/purchases/1/mark_all_received
    # Only the items on requests the viewer may receive for, and with mine=1
    # only those on their own and followed requests, as the list showed.
    def mark_all_purchase
      purchase = authorize policy_scope(Purchase).find(params[:id]), :mark_all_received?
      receiving = Orders::Receiving.new(current_user, policy_scope(OrderRequest), mine: params[:mine].present?)
      purchase.mark_all_received!(by: current_user.person, only: receiving.requests)
      redirect_to after_path, notice: "Everything on this order is marked as here"
    end

    private

    def set_line
      @order_request = authorize policy_scope(OrderRequest).find(params[:request_id]), :receive?
      @line = @order_request.order_lines.find(params[:line_id])
    end

    def delivery_params
      params.fetch(:order_delivery, {}).permit(:quantity, :received_on, :delivery_problem_kind_id, :note, :photo)
    end

    # The problem picked, if any: only an active one can be picked.
    def chosen_problem_kind
      id = delivery_params[:delivery_problem_kind_id].presence
      id && DeliveryProblemKind.active.find(id)
    end

    # Back to the list when the person came from it, else to the request.
    def after_path
      return orders_deliveries_path(mine: params[:mine].presence) if params[:from] == "list"

      @order_request ? orders_request_path(@order_request) : orders_deliveries_path
    end
  end
end
