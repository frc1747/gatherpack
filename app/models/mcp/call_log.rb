# Records every MCP tool call, success or failure, in mcp_tool_calls.
#
# arguments holds only the tool's declared arguments, with each value capped.
# This departs from "as given": a client can send anything, this table has no
# retention job, and admins read it, so undeclared data isn't kept. A tool's
# mask_argument values are stored masked. A failure while masking stores no arguments.
module Mcp::CallLog
  MAX_ARGUMENT_LENGTH = 1_000
  NOT_STORABLE = { "_not_logged" => "arguments could not be stored" }.freeze

  class << self
    def record(ctx:, tool:, arguments:, result:, duration_ms: nil)
      create_row(ctx, tool, loggable_arguments(tool, arguments), result, duration_ms)
    rescue => e
      # The call has already happened, so a row must exist even if its
      # arguments can't be stored.
      Rails.logger.error("[MCP] call log failed (request #{ctx.request_id}): #{e.class}: #{e.message}")
      begin
        create_row(ctx, tool, NOT_STORABLE, result, duration_ms)
      rescue => retry_error
        Rails.logger.error("[MCP] call log retry failed (request #{ctx.request_id}): #{retry_error.class}: #{retry_error.message}")
        nil
      end
    end

    private

    def create_row(ctx, tool, arguments, result, duration_ms)
      McpToolCall.create!(
        user: ctx.user,
        oauth_application_id: ctx.application&.id,
        tool: tool.tool_name,
        arguments: arguments,
        outcome: result.outcome.to_s,
        error_message: result.error&.delete("\0")&.truncate(MAX_ARGUMENT_LENGTH),
        changed_type: result.changed&.class&.name,
        changed_id: result.changed&.id,
        changed_records: result.changed_records.map { |record| { type: record.class.name, id: record.id } },
        duration_ms: duration_ms
      )
    end

    def loggable_arguments(tool, arguments)
      arguments.to_h.slice(*tool.argument_names).to_h do |name, value|
        mask = tool.masked_arguments[name]
        [ name, capped(mask ? mask.call(value) : value) ]
      end
    end

    def capped(value)
      return "[not logged: contains a NUL character]" if Mcp.contains_nul?(value)

      size = value.is_a?(String) ? value.length : value.to_json.length
      size > MAX_ARGUMENT_LENGTH ? "[not logged: #{size} characters]" : value
    end
  end
end
