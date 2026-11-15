module Orders
  # Moves a bought item to another funding source after the fact, with a
  # reason, for funding managers (spec §3.13).
  class ReallocationsController < BaseController
    # POST /orders/requests/1/lines/2/reallocate
    def create
      order_request = OrderRequest.find(params[:request_id])
      line = order_request.order_lines.find(params[:id])
      authorize line, :reallocate?
      source = nil
      if params[:funding_source_id].present?
        source = FundingSource.find_by(id: params[:funding_source_id])
        return redirect_to orders_request_path(order_request), alert: "That funding source wasn't found.", status: :see_other if source.nil?
      end
      line.reallocate_funding!(source, by: current_user.person, reason: params[:reason])
      notice = source ? "Moved to #{source.name}." : "Moved back to the request's funding source."
      redirect_to orders_request_path(order_request), notice: notice, status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to orders_request_path(order_request), alert: e.record.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
