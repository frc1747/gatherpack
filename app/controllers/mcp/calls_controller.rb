# The MCP call log (admins). 404 while the MCP feature is off.
class Mcp::CallsController < InternalController
  # Prepended so signed-out requests get the 404 too, not the sign-in redirect.
  prepend_before_action { head :not_found unless Mcp::Access.enabled? }

  def index
    authorize McpToolCall
    @q = policy_scope(McpToolCall).ransack(params[:q])
    @calls = @q.result.includes(user: :person).order(created_at: :desc, id: :desc).page(params[:page])
    @users = User.where(id: McpToolCall.select(:user_id)).includes(:person).sort_by { |user| user.person&.display_name || user.email }
    @tools = (Mcp.tools.map(&:tool_name) + McpToolCall.distinct.pluck(:tool)).uniq.sort
  end
end
