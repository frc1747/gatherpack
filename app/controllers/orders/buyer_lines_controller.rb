module Orders
  # A buyer's changes to one item after approval (spec §3.4): delayed with
  # an expected date, a new quantity, split (part now, the rest later), or
  # cancelled with a reason.
  class BuyerLinesController < BaseController
    before_action :set_line

    rescue_from ActiveRecord::RecordInvalid do |error|
      redirect_back fallback_location: orders_request_path(@line.order_request),
        alert: error.record.errors.full_messages.to_sentence
    end

    # Back to the item's request, not the request list, when nothing to go back to.
    rescue_from Orders::Refused do |error|
      fallback = @line ? orders_request_path(@line.order_request) : orders_requests_path
      redirect_back fallback_location: fallback, alert: error.message
    end

    # POST /orders/requests/1/lines/2/backorder
    def backorder
      @line.backorder!(by: current_user.person, expected_on: date_param(:expected_on), comment: params[:comment])
      done "#{@line.display_name} is marked delayed."
    end

    # POST /orders/requests/1/lines/2/change_quantity
    def change_quantity
      @line.change_quantity!(params[:quantity].to_i, by: current_user.person, comment: params[:comment])
      if @line.reload.needs_reapproval?
        done "#{@line.display_name} now costs more than was approved, so it needs re-approval."
      else
        done "#{@line.display_name}: quantity changed to #{@line.quantity}."
      end
    end

    # POST /orders/requests/1/lines/2/split
    def split
      rest = @line.split!(params[:quantity_now].to_i, by: current_user.person)
      done "#{@line.display_name} is split: #{@line.reload.quantity} now, #{rest.quantity} later."
    end

    # POST /orders/requests/1/lines/2/cancel
    def cancel
      @line.cancel!(by: current_user.person, reason: params[:reason])
      done "#{@line.display_name} is cancelled."
    end

    private

    def set_line
      order_request = policy_scope(OrderRequest).find(params[:request_id])
      @line = authorize order_request.order_lines.find(params[:id]), :buy?
    end

    def done(notice)
      redirect_back fallback_location: orders_request_path(@line.order_request), notice: notice
    end

    def date_param(key)
      Date.iso8601(params[key]) if params[key].present?
    rescue Date::Error
      raise Orders::Refused, "That isn't a date."
    end
  end
end
