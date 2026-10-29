# Signing out ends every session of the login, not only this browser's: the
# session token is part of what Devise checks session and remember-me
# cookies against (User#authenticatable_salt), so a copy of either cookie
# stops working too. A session that times out doesn't replace it, so the
# login's other devices stay signed in.
Rails.application.config.to_prepare do
  # Signing out always signs out, even when the impersonation has expired or
  # is no longer allowed (check_impersonation would redirect instead); the
  # callback below ends the impersonation.
  Devise::SessionsController.skip_before_action :check_impersonation, only: :destroy
  Devise::SessionsController.before_action only: :destroy do
    end_impersonation("signed out") if current_user != true_user
    true_user&.rotate_session_token!
  end
end

# A sign-out that doesn't go through sessions#destroy (a session timing out)
# clears the session and the impersonation in it with no record; write the
# impersonation's end to the audit log first, as ApplicationController does.
Warden::Manager.before_logout do |user, warden, options|
  impersonated_id = warden.request.session[:impersonated_user_id]
  if user.is_a?(User) && options[:scope] == :user && impersonated_id.present?
    AuditLog.create!(item_type: "User", item_id: impersonated_id, event: "stop_impersonating", whodunnit: user.id)
    Rails.logger.info "[Auth] stop_impersonating: #{user.id} as #{impersonated_id} (session ended)"
  end
end
