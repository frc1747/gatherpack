# MCP connector: inventory. See config/initializers/mcp.rb. Registers only when the inventory
# feature exists in this build; each tool also requires it to be on. Runs after mcp.rb, which
# resets the registry, and after inventory.rb, which registers the feature.
#
# A stock change's reason can say anything about members, so it stays out of the Rails log, on
# refused calls too. Matches both the params and the wrapper's copy. mcp.rb already filters note.
# This covers MCP calls only: the pages' own params aren't filtered here.
Rails.application.config.filter_parameters << "params.arguments.reason"

Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:inventory)

  # Reads
  Mcp.register_tool(Mcp::Tools::ListItems)
  Mcp.register_tool(Mcp::Tools::GetItem)
  Mcp.register_tool(Mcp::Tools::ListLocations)
  Mcp.register_tool(Mcp::Tools::ReorderList)
  Mcp.register_tool(Mcp::Tools::ListMachines)
  Mcp.register_tool(Mcp::Tools::GetUnit)

  # Writes
  Mcp.register_tool(Mcp::Tools::RecordStockMovement)
  Mcp.register_tool(Mcp::Tools::RecordUnitEvent)
end
