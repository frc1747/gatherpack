# The MCP server, as a first trial would run it: flag on, writes off, limited
# to holders of a badge. Adam and Mara hold it; other logins get refused.
# The OAuth application is confidential, the kind that works on every build.
# Its secret is generated here: read it on the OAuth application's page.
# OAuth Provider must be on when the app starts, so restart after a first load
# that changed it.
Hbr::SampleData.feature "feature/mcp" do |s|
  s.enable_feature :oauth_provider
  s.enable_feature :mcp

  admin = s.login(:admin)
  manager = s.login(:manager)

  type = BadgeType.find_or_create_by!(name: "Certification")
  badge = s.upsert!(Badge, { name: "AI Client Access" }, badge_type: type, permission: "added_by_admin", color: "#613583", short: "robot")
  [ admin, manager ].each { |person| BadgeAssignment.find_or_create_by!(badge: badge, person: person) }
  s.setting(:mcp_allowed_badge, badge.neat_id)
  s.setting(:mcp_write_enabled, false)
  s.setting(:mcp_dynamic_pages_enabled, false)

  application = s.upsert!(OauthApplication, { name: "Northwind AI Client" },
    redirect_uri: "https://claude.ai/api/mcp/auth_callback", scopes: "mcp_read mcp_write", confidential: true)

  # What the call log page shows after a little use. Keyed so reloading moves
  # the times forward instead of adding rows.
  log = lambda do |person, tool, outcome, hours_ago, arguments, error_message = nil|
    s.upsert!(McpToolCall, { user_id: person.user_id, tool: tool, outcome: outcome },
      oauth_application: application, arguments: arguments, error_message: error_message,
      duration_ms: 40, created_at: s.clock.hours_ago(hours_ago))
  end
  log.call(admin, "whoami", "ok", 3, {})
  log.call(manager, "search_people", "ok", 2, { "query" => "Ben" })
  log.call(manager, "get_badge", "denied", 1, { "badge_id" => badge.neat_id }, "Not allowed")

  # States the time clock, membership and Page tools act on. Gina's punch is the one
  # clock_out closes. Keyed by its note, so reloading doesn't add another.
  season = s.recall(:season)
  owen = s.person("Gina")
  punch = TimeClockPunch.find_by(person: owen, time_clock_period: season, note: "Open for MCP clock_out") ||
    TimeClockPunch.new(person: owen, time_clock_period: season, note: "Open for MCP clock_out")
  punch.created_by = "kiosk"
  punch.update!(start_time: s.clock.hours_ago(2), end_time: nil)

  applicants = s.team!(:mcp_applicants, "Volunteer Applicants", TeamType.find_by!(name: "Crew"), "#a51d2d", s.team(:programs))
  applicants.update!(join_permission: :requires_approval)
  s.upsert!(MembershipApplication, { person: s.person("Grace"), team: applicants },
    status: :pending, message: "I can help on weekends.")

  s.upsert!(Page, { title: "Volunteer Handbook" }, content: "# Volunteer Handbook\n\nSign in when you arrive.", team: s.team(:root))
  s.upsert!(Page, { title: "My Team Count" }, dynamic: true, team: s.team(:root),
    content: "<p><%= current_user.person.display_name %> is on <%= current_user.person.all_teams.count %> teams.</p>")

  s.report "AI Client Access badge (2 holders), 1 OAuth application, 3 calls in the log, writes off, 1 open punch, 1 pending application, 1 static and 1 dynamic page"
  s.expect("Mara may connect") { Mcp::Access.allowed?(manager.user) }
  s.expect("a login without the badge may not") do
    other = User.where.not(id: [ admin.user_id, manager.user_id ]).first
    other.nil? || !Mcp::Access.allowed?(other)
  end
end
