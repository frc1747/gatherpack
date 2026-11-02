# Records every MCP tool call, success or failure, in mcp_tool_calls.
module Mcp::CallLog
  def self.record(ctx:, tool:, arguments:, result:, changed: nil, duration_ms: nil)
    McpToolCall.create!(
      user: ctx.user,
      oauth_application_id: ctx.application&.id,
      tool: tool.to_s,
      arguments: arguments || {},
      outcome: result.outcome.to_s,
      error_message: result.error,
      changed_type: changed&.class&.name,
      changed_id: changed&.id,
      duration_ms: duration_ms
    )
  rescue => e
    # Never fail the call because the log couldn't be written; a write has
    # already happened by now.
    Rails.logger.error("[MCP] call log failed (request #{ctx.request_id}): #{e.class}: #{e.message}")
    nil
  end
end
