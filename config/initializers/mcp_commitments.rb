# MCP connector for commitments: read tools and manual adjustments. Registers only when the
# commitments feature exists in this build; each tool also requires the
# feature to be on. Runs after mcp.rb, which resets the registry.

# The reason is a note about a member, so it stays out of the Rails log as the
# page's own params do. Matches both the params and the wrapper's copy.
Rails.application.config.filter_parameters << "params.arguments.reason"

Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:commitments)

  Mcp.register_tool(Mcp::Tools::ListCommitments)
  Mcp.register_tool(Mcp::Tools::CommitmentProgress)
  Mcp.register_tool(Mcp::Tools::AddCommitmentAdjustment)
  Mcp.register_tool(Mcp::Tools::RemoveCommitmentAdjustment)
end
