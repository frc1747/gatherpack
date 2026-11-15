module Orders
  # Moves a bought item to another funding source after the fact, with a
  # reason, for funding managers (spec §3.13).
  class ReallocationsController < BaseController
    # POST /orders/requests/1/lines/2/reallocate
    def create
      order_request = OrderRequest.find(params[:request_id])
      line = order_request.order_lines.find(params[:id])
      authorize line, :reallocate?
      source = FundingSource.find_by(id: params[:funding_source_id])
      line.reallocate_funding!(source, by: current_user.person, reason: params[:reason])
      redirect_to orders_request_path(order_request), notice: "Moved to #{source&.name || 'no funding source'}.", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to orders_request_path(order_request), alert: e.record.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
