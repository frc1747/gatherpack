# MCP tools for membership intake (feature :intake): registrations, their
# sign-ups and what managers see beside an application. Initializers load in
# name order, so this runs after mcp.rb's reset and after the checklist
# initializers; it registers only when intake exists in this build.
Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:intake)

  Mcp.register_tool(Mcp::Tools::ListRegistrations)
  Mcp.register_tool(Mcp::Tools::GetRegistration)
  Mcp.register_tool(Mcp::Tools::SetRegistrationState)
  Mcp.register_tool(Mcp::Tools::CopyRegistration)
  Mcp.register_tool(Mcp::Tools::ListIntakeEntries)
  Mcp.register_tool(Mcp::Tools::DeleteIntakeEntries)
  Mcp.register_tool(Mcp::Tools::ListWaitingToFinish)
  Mcp.register_tool(Mcp::Tools::GetApplicationChecklist)
  Mcp.register_tool(Mcp::Tools::DecideMembershipApplications)
end
