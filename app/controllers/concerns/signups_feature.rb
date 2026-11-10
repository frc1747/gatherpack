# Sends people away from every sign-up page while Sign-up Sheets are turned
# off. Routes are always drawn, so turning the feature on or off needs no
# restart.
module SignupsFeature
  extend ActiveSupport::Concern

  included do
    before_action :require_signups_feature
  end

  private

  def require_signups_feature
    redirect_to root_path, notice: "Sign-up sheets are turned off" unless GatherPack::Features.enabled?(:signups)
  end
end
