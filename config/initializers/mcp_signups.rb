# Sign-up sheet tools for the MCP server. Registers after config/initializers/mcp.rb,
# which resets the registry, and only when this build has Sign-up Sheets.

# What a member wrote on a sign-up stays out of the Rails log (see config/initializers/mcp.rb).
Rails.application.config.filter_parameters += %w[answer note].map { |name| "params.arguments.#{name}" }

Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:signups)

  Mcp.register_tool(Mcp::Tools::ListSignupSheets)
  Mcp.register_tool(Mcp::Tools::GetSignupSheet)
  Mcp.register_tool(Mcp::Tools::PersonSignups)
  Mcp.register_tool(Mcp::Tools::PlaceSignup)
  Mcp.register_tool(Mcp::Tools::RemoveSignup)
  Mcp.register_tool(Mcp::Tools::MoveSignup)
  Mcp.register_tool(Mcp::Tools::UpdateSignup)
  Mcp.register_tool(Mcp::Tools::MarkSignup)
  Mcp.register_tool(Mcp::Tools::MarkAllBrought)
end
