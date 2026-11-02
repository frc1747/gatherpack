# What a tool runs as: the token's user and person, the token's scopes, the
# OAuth application and the request id. Tools do their own permission checks
# through it, as the token's user.
class Mcp::Context
  attr_reader :user, :person, :scopes, :application, :request_id

  def initialize(user:, scopes:, application: nil, request_id: nil)
    @user = user
    @person = user.person
    @scopes = Array(scopes).map(&:to_s)
    @application = application
    @request_id = request_id
  end

  # :read is granted by mcp_read or mcp_write; :write only by mcp_write.
  def scope?(level)
    case level.to_sym
    when :read then scopes.intersect?(Mcp::SCOPES)
    when :write then scopes.include?("mcp_write")
    else false
    end
  end

  def writes_allowed?
    scope?(:write) && Mcp::Access.writes_enabled?
  end

  def policy_scope(scope)
    Pundit.policy_scope!(user, scope)
  end

  # Raises Pundit::NotAuthorizedError, which a tool call returns as
  # "Not allowed".
  def authorize!(record, query)
    Pundit.authorize(user, record, query)
  end

  # The record with this neat ID in scope, or Mcp::NotFound: a wrong prefix
  # and a record the user can't see look the same.
  def find(scope, neat_id)
    Mcp.find_by_neat_id(scope, neat_id) || raise(Mcp::NotFound)
  end
end
