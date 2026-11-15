# Base of every inventory controller: turns requests away while the feature
# is off, and shows a refused domain action as a flash.
module Inventory
  class BaseController < InternalController
    before_action :require_feature

    rescue_from Inventory::Refused do |error|
      redirect_back fallback_location: inventory_root_path, alert: error.message
    end

    private

    def require_feature
      redirect_to root_path, notice: "Inventory is turned off" unless Inventory.enabled?
    end
  end
end
