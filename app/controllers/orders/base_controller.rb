# Base of every orders controller: turns requests away while the feature
# is off, and shows a refused domain action as a flash.
module Orders
  class BaseController < InternalController
    before_action :require_feature

    rescue_from Orders::Refused do |error|
      if prefetch?
        head :forbidden
      else
        redirect_back fallback_location: orders_requests_path, alert: error.message
      end
    end

    private

    # A refused page that the browser only prefetched (a hover) must not
    # leave its "not allowed" flash for whatever page the member opens next.
    def pundit_not_authorized
      prefetch? ? head(:forbidden) : super
    end

    def prefetch?
      request.headers["X-Sec-Purpose"].to_s.start_with?("prefetch") || request.headers["Sec-Purpose"].to_s.start_with?("prefetch")
    end

    def require_feature
      return if Orders.enabled?

      prefetch? ? head(:forbidden) : redirect_to(root_path, notice: "Orders are turned off")
    end
  end
end
