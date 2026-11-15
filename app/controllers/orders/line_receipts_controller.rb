module Orders
  # The buyer's receiving actions on one item (spec §3.6): mark it received
  # with no delivery record, and settle a problem delivery.
  class LineReceiptsController < BaseController
    before_action :set_line

    # POST /orders/requests/1/lines/2/mark_received
    def mark_received
      authorize @line, :mark_received?
      @line.mark_received!(by: current_user.person, note: params[:note])
      redirect_to orders_request_path(@order_request), notice: "Marked as here: #{@line.display_name}"
    end

    # POST /orders/requests/1/lines/2/resolve
    def resolve
      authorize @line, :buy?
      @line.resolve_problem!(params[:resolution], by: current_user.person, comment: params[:comment], quantity: params[:quantity].presence)
      redirect_to orders_request_path(@order_request),
        notice: params[:resolution] == "reorder" ? "Ordering a replacement for #{@line.display_name}" : "Cancelled: #{@line.display_name}"
    end

    private

    def set_line
      @order_request = policy_scope(OrderRequest).find(params[:request_id])
      @line = @order_request.order_lines.find(params[:id])
    end
  end
end
