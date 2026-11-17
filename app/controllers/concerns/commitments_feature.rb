# Commitments' routes are always drawn; its controllers send people away
# while the feature is off.
module CommitmentsFeature
  extend ActiveSupport::Concern

  included do
    before_action :require_commitments_feature
  end

  private

  def require_commitments_feature
    redirect_to root_path, notice: "Commitments are turned off" unless GatherPack::Features.enabled?(:commitments)
  end
end
