# Base of every orders controller: turns requests away while the feature
# is off, and shows a refused domain action as a flash.
module Orders
  class BaseController < InternalController
    before_action :require_feature

    rescue_from Orders::Refused do |error|
      redirect_back fallback_location: orders_requests_path, alert: error.message
    end

    private

    def require_feature
      redirect_to root_path, notice: "Orders are turned off" unless Orders.enabled?
    end
  end
end
