# Sign-up sheet tools for the MCP server. Registers after config/initializers/mcp.rb,
# which resets the registry, and only when this build has Sign-up Sheets.
Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:signups)

  Mcp.register_tool(Mcp::Tools::ListSignupSheets)
  Mcp.register_tool(Mcp::Tools::GetSignupSheet)
  Mcp.register_tool(Mcp::Tools::PersonSignups)
end
