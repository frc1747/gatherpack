Rails.application.config.to_prepare do
  Doorkeeper::AuthorizationsController.include(OauthAuthorizationReturn::StoreSignedOutRequest)
  Doorkeeper::AuthorizationsController.prepend_before_action :store_oauth_authorization_return, only: :new

  Devise::SessionsController.include(OauthAuthorizationReturn::ReturnAfterSignOut)
end
