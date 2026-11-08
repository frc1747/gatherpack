class WelcomeController < ApplicationController
  # index sends signed-out visitors to sign in itself, without the notice.
  skip_before_action :check_for_user, only: :index

  def index
    if user_signed_in?
      @shortcuts = policy_scope(Shortcut).order(:updated_at)
      @announcements = policy_scope(Announcement).visible.order(start_time: :asc, end_time: :asc)
      render :dashboard
    else
      redirect_to new_user_session_path
    end
  end

  def setup
  end
end
