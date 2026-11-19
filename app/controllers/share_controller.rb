# Landing page for links and text shared to the installed app from another app.
class ShareController < InternalController
  before_action :require_installable_app

  # GET /share
  def show
    authorize :share, :show?
    @shared = GatherPack::ShareActions.shared_from(params)
    @actions = GatherPack::ShareActions.visible_for(current_user)

    if @actions.one?
      redirect_to GatherPack::ShareActions.path_for(@actions.first, @shared)
    end
  end

  private

  def require_installable_app
    head :not_found unless GatherPack::Features.enabled?(:installable_app)
  end
end
