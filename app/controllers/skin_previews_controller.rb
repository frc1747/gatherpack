# Lets an admin try the modern skin in their own session.
class SkinPreviewsController < ApplicationController
  before_action :check_for_admin, only: :create

  def create
    session[:skin_preview] = true
    redirect_to edit_theme_path, status: :see_other
  end

  # Open to any signed-in session: an admin may be impersonating someone.
  def destroy
    session.delete(:skin_preview)
    redirect_to root_path, status: :see_other
  end
end
