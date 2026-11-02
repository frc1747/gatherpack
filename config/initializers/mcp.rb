# MCP server: lets members' AI clients read (and, when allowed, change)
# GatherPack data as the member, through OAuth tokens with the mcp_read and
# mcp_write scopes. See app/models/mcp.rb for the tool registry and how
# connector initializers (config/initializers/mcp_<feature>.rb) add tools.
Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :mcp,
      label: "MCP server",
      description: "Let members' AI clients read and change data as the member, within their permissions",
      default_enabled: false,
      toggleable: true,
      setup_section: "People",
      nav_position: 90,
      setup_items: [
        GatherPack::Feature::SetupItem.new(
          label: "MCP Calls",
          path: :mcp_calls_path,
          # The route exists only while oauth_provider was on at boot.
          policy_check: ->(view) { view.admin? && view.respond_to?(:mcp_calls_path) }
        )
      ]
    )
  )

  # Settings.register may not exist; fall back to add_setting (same argument order).
  register_setting = lambda do |*args|
    if Settings.respond_to?(:register)
      Settings.register(*args)
    else
      Settings.instance.send(:add_setting, *args)
    end
  end
  register_setting.call(:mcp_allowed_badge, :string, "MCP: allowed badge", "", "MCP",
    "Neat ID (bdg_...) of the badge whose holders can connect. Blank: every member.")
  register_setting.call(:mcp_write_enabled, :boolean, "MCP: allow changes", "false", "MCP",
    "Off: MCP clients can only read.")

  # Scopes: Doorkeeper's config isn't frozen, and every scope check reads
  # Doorkeeper.config.scopes (memoized default + optional), so add to both.
  Mcp::SCOPES.each do |scope|
    Doorkeeper.config.optional_scopes.add(scope)
    Doorkeeper.config.scopes.add(scope)
  end

  Doorkeeper::AuthorizationsController.include(Mcp::AuthorizationChecks)

  # Core tools, one line each, in the order tools/list shows them.
  Mcp.reset!
  Mcp.register_tool(Mcp::Tools::Whoami)
  Mcp.register_tool(Mcp::Tools::SearchPeople)

  # People, teams, badges
  Mcp.register_tool(Mcp::Tools::GetPerson)
  Mcp.register_tool(Mcp::Tools::ListTeams)
  Mcp.register_tool(Mcp::Tools::GetTeam)
  Mcp.register_tool(Mcp::Tools::ListBadges)
  Mcp.register_tool(Mcp::Tools::GetBadge)

  # Events, time, ledgers
  Mcp.register_tool(Mcp::Tools::ListEvents)
  Mcp.register_tool(Mcp::Tools::GetEvent)
  Mcp.register_tool(Mcp::Tools::ListCheckins)
  Mcp.register_tool(Mcp::Tools::TimeClockHours)
  Mcp.register_tool(Mcp::Tools::ClockedInNow)
  Mcp.register_tool(Mcp::Tools::ListLedgers)
  Mcp.register_tool(Mcp::Tools::LedgerEntries)
end
