# Opening the home page while signed out goes straight to sign in. The
# "You must be logged in" notice is for pages someone tried to reach.
Rails.application.config.to_prepare do
  WelcomeController.prepend_before_action(only: :index) do
    unless current_user
      # Same return path check_for_user would have stored for "/".
      session[:user_return_to] = root_path
      redirect_to new_user_session_path
    end
  end
end
