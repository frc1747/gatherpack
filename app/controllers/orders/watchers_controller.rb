module Orders
  # The requester (or a team manager) adds people to follow a request, and
  # takes them off again. People follow and stop following themselves from
  # the request page (RequestsController#follow).
  class WatchersController < BaseController
    before_action :set_order_request

    # POST /orders/requests/1/watchers
    def create
      person = Orders::WatcherCandidates.for(@order_request).find_by(id: params[:person_id])
      if person
        @order_request.follow!(person)
        redirect_to orders_request_path(@order_request, anchor: "following"), notice: "#{person.identifier_name} is following this request"
      else
        redirect_to orders_request_path(@order_request, anchor: "following"), alert: "Choose someone from the list"
      end
    end

    # DELETE /orders/requests/1/watchers/1
    def destroy
      watcher = @order_request.order_request_watchers.find(params[:id])
      @order_request.unfollow!(watcher.person)
      redirect_to orders_request_path(@order_request, anchor: "following"), notice: "#{watcher.person.identifier_name} stopped following"
    end

    private

    def set_order_request
      @order_request = authorize policy_scope(OrderRequest).find(params[:request_id]), :add_watchers?
    end
  end
end
