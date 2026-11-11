# Lets an admin try the modern skin in their own session.
class SkinPreviewsController < InternalController
  before_action :check_for_admin, only: :create

  # A flag on this browser session, with no record to authorize.
  def create
    skip_authorization
    session[:skin_preview] = true
    redirect_to edit_theme_path, status: :see_other
  end

  # Open to any signed-in session: an admin may be impersonating someone.
  def destroy
    skip_authorization
    session.delete(:skin_preview)
    redirect_to root_path, status: :see_other
  end
end
