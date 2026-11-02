# Lets an OAuth authorization request survive signing in. The only location
# accepted is the authorization endpoint itself, so a return value can't send
# anyone further than /oauth/authorize already could.
module OauthAuthorizationReturn
  # The location is kept in the session cookie, which browsers drop above 4KB.
  # Counted as JSON, as stored: & becomes &, and encrypting the session
  # nearly doubles it. This leaves room for the rest of the session.
  MAX_STORED_BYTES = 1500

  def self.accepts?(location)
    return false unless location.is_a?(String) && location.start_with?("/") && !location.start_with?("//")

    routes = Rails.application.routes.url_helpers
    return false unless routes.respond_to?(:oauth_authorization_path)

    URI.parse(location).path == routes.oauth_authorization_path && location.to_json.bytesize <= MAX_STORED_BYTES
  rescue URI::InvalidURIError
    false
  end

  module StoreSignedOutRequest
    private

    def store_oauth_authorization_return
      return if current_user || !request.get? || !OauthAuthorizationReturn.accepts?(request.fullpath)

      store_location_for(:user, request.fullpath)
    end
  end

  module ReturnAfterSignOut
    # Signing out resets the session, so nothing can be stored until it's done.
    # Going back to the request does it: signed out, the request stores itself
    # and sends the visitor to sign in.
    def after_sign_out_path_for(resource_or_scope)
      location = params[:oauth_return_to]
      OauthAuthorizationReturn.accepts?(location) ? location : super
    end
  end
end
