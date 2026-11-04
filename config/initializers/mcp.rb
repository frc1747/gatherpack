# MCP server: lets members' AI clients read (and, when allowed, change)
# GatherPack data as the member, through OAuth tokens with the mcp_read and
# mcp_write scopes. See app/models/mcp.rb for the tool registry and how
# connector initializers (config/initializers/mcp_<feature>.rb) add tools.
# Personal details in tool arguments stay out of the Rails log, as the pages' own
# params do. Matches both the params and the wrapper's copy. Those the tools don't
# take are here too: a client may send them, and it's refused only after the log line.
Rails.application.config.filter_parameters += %w[first_name last_name display_name bio phone_number address birthday gender shirt_size dietary_restrictions]
  .map { |name| "params.arguments.#{name}" }
# A token's value logs its holder in at the kiosk; a punch's note can say anything. A
# client may send a value under another name, which is refused only after the log line.
# These match substrings, so token also hides token_id, which is no loss.
Rails.application.config.filter_parameters += %w[value note token rfid card].map { |name| "params.arguments.#{name}" }
# A page's query string can hold anything the page takes.
Rails.application.config.filter_parameters += [ "params.arguments.params" ]

Rails.application.config.to_prepare do
  # Mcp::Access reads the settings store on every request, so transactions
  # must wait for each other instead of raising when requests overlap.
  Settings.instance.store = PStore.new(Settings.instance.store.path, true)

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :mcp,
      label: "MCP server",
      description: "Let members' AI clients read and change data as the member, within their permissions",
      default_enabled: false,
      toggleable: true,
      nav_position: 90
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
  # :mcp_badge renders as McpBadgeInput (a select by name) on the settings
  # page, with the app's select styling.
  SimpleForm.wrapper_mappings = (SimpleForm.wrapper_mappings || {}).merge(mcp_badge: :vertical_select)
  register_setting.call(:mcp_allowed_badge, :mcp_badge, "MCP: allowed badge", "", "MCP",
    "Only people with this badge can connect. Every member: no limit.")
  register_setting.call(:mcp_write_enabled, :boolean, "MCP: allow changes", "false", "MCP",
    "Off: MCP clients can only read. Clients connected while this was off must reconnect to make changes.")
  register_setting.call(:mcp_dynamic_pages_enabled, :boolean, "MCP: read dynamic pages", "false", "MCP",
    "Off: MCP clients can read static pages only. Dynamic pages can show minors' contact details, which MCP otherwise withholds.")

  # Scopes: Doorkeeper's config isn't frozen, and every scope check reads
  # Doorkeeper.config.scopes (memoized default + optional), so add to both.
  Mcp::SCOPES.each do |scope|
    Doorkeeper.config.optional_scopes.add(scope)
    Doorkeeper.config.scopes.add(scope)
  end

  # A worker's copy of these settings can be stale; refresh before the page
  # shows them, so a full-form save from here can't write old values back.
  SettingsController.before_action(only: :index) { Mcp::Access.refresh_settings }

  Doorkeeper::AuthorizationsController.include(Mcp::AuthorizationChecks)

  # Core tools, one line each, in the order tools/list shows them.
  Mcp.reset!
  Mcp.register_tool(Mcp::Tools::Whoami)
  Mcp.register_tool(Mcp::Tools::SearchPeople)
  Mcp.register_tool(Mcp::Tools::FindDuplicatePeople)

  # People, teams, badges
  Mcp.register_tool(Mcp::Tools::GetPerson)
  Mcp.register_tool(Mcp::Tools::ListTeams)
  Mcp.register_tool(Mcp::Tools::GetTeam)
  Mcp.register_tool(Mcp::Tools::ListBadges)
  Mcp.register_tool(Mcp::Tools::GetBadge)

  # Events, time, ledgers
  Mcp.register_tool(Mcp::Tools::ListEvents)
  Mcp.register_tool(Mcp::Tools::GetEvent)
  Mcp.register_tool(Mcp::Tools::ListEventTypes)
  Mcp.register_tool(Mcp::Tools::ListCheckins)
  Mcp.register_tool(Mcp::Tools::TimeClockHours)
  Mcp.register_tool(Mcp::Tools::ClockedInNow)
  Mcp.register_tool(Mcp::Tools::ListLedgers)
  Mcp.register_tool(Mcp::Tools::LedgerEntries)

  # Writes
  Mcp.register_tool(Mcp::Tools::CreatePerson)
  Mcp.register_tool(Mcp::Tools::UpdatePerson)
  Mcp.register_tool(Mcp::Tools::AddLogin)
  Mcp.register_tool(Mcp::Tools::AssignBadge)
  Mcp.register_tool(Mcp::Tools::RemoveBadge)
  Mcp.register_tool(Mcp::Tools::AddTeamMember)
  Mcp.register_tool(Mcp::Tools::RemoveTeamMember)
  Mcp.register_tool(Mcp::Tools::RecordCheckin)
  Mcp.register_tool(Mcp::Tools::CreateEvent)

  # Time clock
  Mcp.register_tool(Mcp::Tools::ListTimeClockPeriods)
  Mcp.register_tool(Mcp::Tools::ListPunches)
  Mcp.register_tool(Mcp::Tools::RecordPunch)
  Mcp.register_tool(Mcp::Tools::UpdatePunch)
  Mcp.register_tool(Mcp::Tools::RemovePunch)
  Mcp.register_tool(Mcp::Tools::ClockOut)
  Mcp.register_tool(Mcp::Tools::ListTokens)
  Mcp.register_tool(Mcp::Tools::AddToken)
  Mcp.register_tool(Mcp::Tools::RemoveToken)

  # Pages and reads
  Mcp.register_tool(Mcp::Tools::ListPages)
  Mcp.register_tool(Mcp::Tools::GetPage)
  Mcp.register_tool(Mcp::Tools::GetPageSource)
  Mcp.register_tool(Mcp::Tools::ListAnnouncements)
  Mcp.register_tool(Mcp::Tools::CreateAnnouncement)
  Mcp.register_tool(Mcp::Tools::ListCalendarNotes)
  Mcp.register_tool(Mcp::Tools::ListQuestions)
  Mcp.register_tool(Mcp::Tools::GetQuestion)
  Mcp.register_tool(Mcp::Tools::ListEventCheckinFields)
end
