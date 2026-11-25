module Orders
  class DecisionsController < BaseController
    DONE_WORDS = {
      "approved" => "Approved",
      "changes_requested" => "Sent back for changes",
      "declined" => "Declined"
    }.freeze

    # POST /orders/requests/1/decisions
    # Approve, ask for changes or decline (spec §3.3), after setting the
    # funding source when the request had none. OrderRequest#decide! refuses
    # anyone who can't decide, with the reason, so the page can say it.
    def create
      @order_request = authorize policy_scope(OrderRequest).find(params[:request_id]), :show?
      person = current_user.person
      refusal = @order_request.decision_refusal(person)
      raise Orders::Refused, refusal if refusal

      set_funding_source(person)
      @order_request.decide!(params[:decision], by: person, comment: params[:comment],
        fits_restriction: params[:fits_restriction] == "1")
      redirect_to orders_approvals_path, notice: "#{DONE_WORDS.fetch(params[:decision])}: #{@order_request.display_title}"
    end

    private

    # The picker shows only while the request has no funding source. The
    # choice is kept even if the decision is refused, so the page then
    # shows the source's restriction and numbers.
    def set_funding_source(person)
      return if params[:funding_source_id].blank? || @order_request.funding_source_id.present?

      source = policy_scope(FundingSource).active.find(params[:funding_source_id])
      @order_request.edit!({ funding_source_id: source.id }, by: person)
    rescue ActiveRecord::RecordInvalid => error
      raise Orders::Refused, error.record.errors.full_messages.to_sentence
    end
  end
end
