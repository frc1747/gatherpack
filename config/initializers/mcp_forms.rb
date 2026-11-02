# MCP connector: forms (read tools). See config/initializers/mcp.rb.
Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:forms)

  Mcp.register_tool(Mcp::Tools::ListForms)
  Mcp.register_tool(Mcp::Tools::FormStatus)
  Mcp.register_tool(Mcp::Tools::FormAnswers)
end
