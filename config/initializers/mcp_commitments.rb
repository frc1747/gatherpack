# MCP connector for commitments: read tools. Registers only when the
# commitments feature exists in this build; each tool also requires the
# feature to be on. Runs after mcp.rb, which resets the registry.
Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:commitments)

  Mcp.register_tool(Mcp::Tools::ListCommitments)
  Mcp.register_tool(Mcp::Tools::CommitmentProgress)
end
