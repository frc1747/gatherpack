# OAuth discovery documents for MCP clients: protected resource metadata
# (RFC 9728) and authorization server metadata (RFC 8414). 404 while the MCP
# feature is off.
class Mcp::MetadataController < ActionController::API
  before_action { head :not_found unless Mcp::Access.enabled? }

  def protected_resource
    render json: {
      resource: mcp_url,
      authorization_servers: [ request.base_url ],
      scopes_supported: Mcp::SCOPES,
      bearer_methods_supported: [ "header" ]
    }
  end

  # Advertises PKCE and public clients ("none") only where they are enforced;
  # see Mcp::RequirePkce.
  def authorization_server
    document = {
      issuer: request.base_url,
      authorization_endpoint: oauth_authorization_url,
      token_endpoint: oauth_token_url,
      revocation_endpoint: oauth_revoke_url,
      scopes_supported: Doorkeeper.config.scopes.to_a,
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      token_endpoint_auth_methods_supported: [ "client_secret_post", "client_secret_basic" ]
    }
    if Mcp.pkce_supported?
      document[:code_challenge_methods_supported] = [ "S256" ]
      document[:token_endpoint_auth_methods_supported] += [ "none" ]
    end

    render json: document
  end
end
