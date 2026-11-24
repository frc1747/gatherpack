# Housekeeping's routes are always drawn; its controllers send people away
# while the feature is off.
module HousekeepingFeature
  extend ActiveSupport::Concern

  included do
    before_action :require_housekeeping_feature
  end

  private

  def require_housekeeping_feature
    redirect_to root_path, notice: "Housekeeping is turned off" unless Housekeeping.enabled?
  end
end
