# Lets an OAuth authorization request survive signing in. The only location
# accepted is the authorization endpoint itself, so a return value can't send
# anyone further than /oauth/authorize already could.
module OauthAuthorizationReturn
  # The location is kept in the session cookie, which overflows at 4KB.
  MAX_LENGTH = 2000

  def self.accepts?(location)
    return false unless location.is_a?(String) && location.bytesize <= MAX_LENGTH

    routes = Rails.application.routes.url_helpers
    return false unless routes.respond_to?(:oauth_authorization_path)

    uri = URI.parse(location)
    uri.scheme.nil? && uri.host.nil? && uri.path == routes.oauth_authorization_path
  rescue URI::InvalidURIError
    false
  end

  # Signing out resets the session, so nothing can be stored until it's done.
  # Going back to the request does it: signed out, the request stores itself
  # and sends the visitor to sign in.
  def after_sign_out_path_for(resource_or_scope)
    location = params[:oauth_return_to]
    OauthAuthorizationReturn.accepts?(location) ? location : super
  end
end
