Rails.application.config.to_prepare do
  Devise::SessionsController.include(OauthAuthorizationReturn)
end
