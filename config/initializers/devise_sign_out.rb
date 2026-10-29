# Signing out ends every session of the login, not only this browser's: the
# session token is part of what Devise checks session and remember-me
# cookies against (User#authenticatable_salt), so a copy of either cookie
# stops working too. A session that times out doesn't replace it, so the
# login's other devices stay signed in.
Rails.application.config.to_prepare do
  Devise::SessionsController.before_action only: :destroy do
    true_user&.rotate_session_token!
  end
end
