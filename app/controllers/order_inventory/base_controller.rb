# Base of the order-inventory controllers: turns requests away unless both
# orders and inventory are on, and shows a refused action as a flash.
module OrderInventory
  class BaseController < InternalController
    before_action :require_features

    rescue_from Orders::Refused, Inventory::Refused do |error|
      redirect_back fallback_location: orders_requests_path, alert: error.message
    end

    private

    def require_features
      redirect_to root_path, notice: "Orders and inventory aren't both turned on" unless OrderInventory.enabled?
    end
  end
end
