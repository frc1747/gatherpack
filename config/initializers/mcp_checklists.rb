# MCP connector: checklists. See config/initializers/mcp.rb. Registers only when the checklists
# feature exists in this build; each tool also requires it to be on. Runs after mcp.rb, which
# resets the registry.
#
# The reason of an adjustment or excuse and the note of a recorded list are notes about members, so
# they stay out of the Rails log, on refused calls too. Matches both the params and the wrapper's
# copy. This covers MCP calls only: the pages' own params aren't filtered here.
Rails.application.config.filter_parameters << "params.arguments.reason"
Rails.application.config.filter_parameters << "params.arguments.note"

Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:checklists)

  Mcp.register_tool(Mcp::Tools::ListChecklists)
  Mcp.register_tool(Mcp::Tools::ChecklistStatus)
  Mcp.register_tool(Mcp::Tools::ChecklistResults)
  Mcp.register_tool(Mcp::Tools::PeopleMeeting)
  Mcp.register_tool(Mcp::Tools::AddCreditAdjustment)
  Mcp.register_tool(Mcp::Tools::RemoveCreditAdjustment)
  Mcp.register_tool(Mcp::Tools::ExcuseItem)
  Mcp.register_tool(Mcp::Tools::RemoveExcuse)
  Mcp.register_tool(Mcp::Tools::AttestItem)
  Mcp.register_tool(Mcp::Tools::CopyChecklist)
  Mcp.register_tool(Mcp::Tools::RecordList)
end
