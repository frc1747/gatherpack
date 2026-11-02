# The MCP endpoint (Streamable HTTP, stateless). Each POST is one JSON-RPC
# message, answered with application/json: no sessions, no
# Mcp-Session-Id, no SSE streams, so GET and DELETE answer 405.
#
# This controller authenticates the bearer token and checks Mcp::Access;
# each tool does its own permission checks as the token's user. It inherits
# ActionController::API, so there is no session or cookie to fall back on.
class McpController < ActionController::API
  before_action :require_mcp_feature
  before_action :check_origin, only: :create
  before_action :authenticate_token, only: :create
  rate_limit to: 120, within: 1.minute, by: -> { @token.id }, with: -> { render_rate_limited }, only: :create
  before_action :check_access, only: :create

  def create
    ctx = Mcp::Context.new(user: @user, scopes: @token.scopes.to_a, application: @token.application, request_id: request.request_id)
    status, headers, body = Mcp::Server.new(ctx).handle(request)
    # The transport only answers with a stream for subscriptions, which this server doesn't offer.
    return render_jsonrpc_error(:method_not_allowed, "Streams aren't supported") unless body.respond_to?(:each)

    headers.each { |name, value| response.set_header(name, value) }
    self.status = status
    self.response_body = body
  end

  def method_not_allowed
    response.set_header("Allow", "POST")
    head :method_not_allowed
  end

  private

  def require_mcp_feature
    head :not_found unless Mcp::Access.enabled?
  end

  # MCP transport guidance: refuse browser requests from other origins
  # (DNS rebinding). Native clients send no Origin.
  def check_origin
    origin = request.headers["Origin"]
    return if origin.blank? || origin == request.base_url

    render_jsonrpc_error(:forbidden, "Origin not allowed")
  end

  # Bearer header only (no access_token parameter), as the protected
  # resource metadata advertises.
  def authenticate_token
    @token = Doorkeeper::OAuth::Token.authenticate(request, :from_bearer_authorization)
    @user = User.find_by(id: @token.resource_owner_id) if @token&.accessible?
    return render_unauthorized if @user.nil?

    unless Mcp::SCOPES.any? { |scope| @token.scopes.exists?(scope) }
      response.set_header("WWW-Authenticate", %(Bearer error="insufficient_scope", scope="mcp_read", resource_metadata="#{resource_metadata_url}"))
      render_jsonrpc_error(:forbidden, "This token has no MCP scope")
    end
  end

  def check_access
    render_jsonrpc_error(:forbidden, "MCP isn't enabled for your account") unless Mcp::Access.allowed?(@user)
  end

  def render_unauthorized
    challenge = %(Bearer resource_metadata="#{resource_metadata_url}")
    challenge += %(, error="invalid_token") if request.authorization.present?
    response.set_header("WWW-Authenticate", challenge)
    render_jsonrpc_error(:unauthorized, "Sign in required")
  end

  def render_rate_limited
    render_jsonrpc_error(:too_many_requests, "Too many requests")
  end

  def render_jsonrpc_error(status, message)
    render status: status, json: { jsonrpc: "2.0", id: nil, error: { code: -32_000, message: message } }
  end

  def resource_metadata_url
    "#{request.base_url}/.well-known/oauth-protected-resource"
  end
end
