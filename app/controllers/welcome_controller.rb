class WelcomeController < InternalController
  def index
    if user_signed_in?
      @shortcuts = policy_scope(Shortcut).order(:updated_at)
      @announcements = policy_scope(Announcement).visible.order(start_time: :asc, end_time: :asc)
      render :dashboard
    else
      redirect_to new_user_session_path
    end
  end

  # Only links to other pages, which check their own policies.
  def setup
    skip_authorization
  end
end
