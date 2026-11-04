# The world for MCP tests:
#
#   Alpha: alpha_manager (manager), alpha_member, ward
#   Beta: beta_member, badge_holder
#
# The two teams share no ancestor: PersonPolicy::Scope lets a member see
# everyone under their teams' ancestors, so a shared parent would make the
# whole tree visible. admin is an admin in no team. guardian is "Parent of"
# ward and in no team. badge_holder holds the access badge (team-less,
# admin-assigned). Every person has a user.
#
# Tests using this world get the MCP feature (and oauth_provider) turned on
# for each test, in a throwaway settings store. Turn it off again with
# with_feature(:mcp, false) { }.
#
#   call_tool("search_people", user: user(:admin), query: "World")   # => Mcp::Tool::Result
#   mcp_post(mcp_token(user(:admin)), "tools/list")                  # => parsed JSON-RPC response
module McpWorld
  def self.included(base)
    base.setup { @restore_mcp_feature = apply_settings(feature_mcp: "true", feature_oauth_provider: "true") }
    base.teardown { @restore_mcp_feature&.call }
  end

  def build_mcp_world
    @alpha = create_world_team("Alpha")
    @beta = create_world_team("Beta")

    @people = {}
    @people[:admin] = create_world_person("Admin", admin: true)
    @people[:alpha_manager] = create_world_person("AlphaManager", @alpha, manager: true)
    @people[:alpha_member] = create_world_person("AlphaMember", @alpha)
    @people[:ward] = create_world_person("Ward", @alpha)
    @people[:beta_member] = create_world_person("BetaMember", @beta)
    @people[:guardian] = create_world_person("Guardian")
    @people[:badge_holder] = create_world_person("BadgeHolder", @beta)

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin)
    Relationship.create!(parent: person(:guardian), child: person(:ward), relationship_type: @parent_of, created_by: person(:admin))

    @access_badge = create_world_badge("MCP Access")
    BadgeAssignment.create!(badge: @access_badge, person: person(:badge_holder))
  end

  def person(name)
    @people.fetch(name)
  end

  def user(name)
    person(name).user
  end

  # Runs a tool the way the server does (scope, feature and argument checks,
  # time zone, audit user, call log) and returns its Mcp::Tool::Result.
  #
  # By default the token has the tool's own scope and a write tool has writes
  # switched on, so a refusal comes from the tool's permission check. To test
  # those two gates, pass scopes: or writes_enabled: false.
  #
  # Fails the test if a successful result doesn't match the tool's output
  # schema, or a successful write tool that isn't bulk didn't call changed!.
  def call_tool(name, user:, scopes: nil, writes_enabled: nil, **arguments)
    tool = Mcp.tool(name) || flunk("No MCP tool #{name}")
    scopes ||= tool.write? ? "mcp_write" : "mcp_read"
    writes_enabled = true if writes_enabled.nil? && tool.write?
    context = mcp_context(user, scopes: scopes)
    result = if writes_enabled.nil?
      tool.run(context, arguments)
    else
      with_settings(mcp_write_enabled: writes_enabled.to_s) { tool.run(context, arguments) }
    end

    unless result.error?
      MCP::Tool::OutputSchema.new(tool.output_schema).validate_result(result.value) if tool.output_schema
      flunk("MCP write tool #{name} succeeded without calling changed!") if tool.write? && !tool.bulk? && result.changed.nil?
    end
    result
  end

  def mcp_context(user, scopes: "mcp_read")
    Mcp::Context.new(user: user, scopes: scopes.to_s.split, request_id: "test")
  end

  def mcp_application
    @mcp_application ||= OauthApplication.create!(name: "MCP Client", redirect_uri: "https://client.example.com/callback",
      scopes: "mcp_read mcp_write", confidential: true)
  end

  def mcp_token(user, scopes: "mcp_read")
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: mcp_application.id, scopes: scopes, expires_in: 2.hours)
  end

  # Posts one JSON-RPC request to /mcp and returns the parsed response body.
  # token may be nil (no Authorization header).
  def mcp_post(token, method, params = {}, id: 1, headers: {})
    message = { jsonrpc: "2.0", id: id, method: method }
    message[:params] = params if params.present?
    post "/mcp", params: message.to_json, headers: mcp_headers(token).merge(headers)
    response.parsed_body
  end

  # The headers an MCP client sends on a POST.
  def mcp_headers(token)
    headers = { "Accept" => "application/json, text/event-stream", "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{token.plaintext_token}" if token
    headers
  end

  # Makes Doorkeeper report PKCE support (or not) for the duration of the block,
  # whether or not this build's grants table has the columns. With true, don't
  # let a grant get created inside the block: the columns may not be there.
  def with_pkce_supported(value)
    Doorkeeper::AccessGrant.define_singleton_method(:pkce_supported?) { value }
    yield
  ensure
    Doorkeeper::AccessGrant.singleton_class.send(:remove_method, :pkce_supported?)
  end

  # Registers tool for the duration of the block.
  def with_tool(tool)
    Mcp.register_tool(tool)
    yield
  ensure
    Mcp.unregister_tool(tool.tool_name)
  end

  # Events, time clock and ledgers for the core read tools (call after
  # build_mcp_world). Times are in March 2026; tests that count open punches
  # travel_to NOW.
  #
  #   Alpha event "Alpha Meeting" (alpha_member, ward checked in), Beta event
  #   "Beta Meeting" (beta_member), and "Open Day" with no team (admin only).
  #   Periods: "Alpha March" (Alpha), "Beta March" (Beta), "Everyone March" (no team).
  #   Punches: alpha_member 2h, ward 1h, alpha_manager 3h and an open one since
  #   3/11 08:00, beta_member 4h and an open one since 3/11 09:00 (hours 0.05-rounded).
  #   Ledgers: "Alpha Fund" (Alpha; +50.00 "Dues", -12.50 "Snacks" and a pending
  #   +5.00), "Beta Fund" (Beta, +20.00 "Dues" split in two).
  MCP_TIME_NOW = Time.utc(2026, 3, 12, 12, 0)

  def build_mcp_time_world
    meeting = Time.utc(2026, 3, 10, 18, 0)
    @alpha_event = create_world_event("Alpha Meeting", @alpha, meeting)
    @beta_event = create_world_event("Beta Meeting", @beta, meeting + 1.day)
    @open_event = create_world_event("Open Day", nil, meeting + 2.days)
    [ :alpha_member, :ward ].each { |name| create_world_checkin(person(name), @alpha_event) }
    create_world_checkin(person(:beta_member), @beta_event)
    create_world_checkin(person(:alpha_member), @open_event)

    @alpha_period = create_world_period("Alpha March", @alpha)
    @beta_period = create_world_period("Beta March", @beta)
    @everyone_period = create_world_period("Everyone March", nil)
    create_world_punch(person(:alpha_member), @alpha_period, 9, 11)
    create_world_punch(person(:ward), @alpha_period, 9, 10)
    create_world_punch(person(:alpha_manager), @alpha_period, 9, 12)
    @open_punch = create_world_punch(person(:alpha_manager), @alpha_period, 32, nil)
    create_world_punch(person(:beta_member), @beta_period, 9, 13)
    create_world_punch(person(:beta_member), @beta_period, 33, nil)

    @dues = LedgerTag.create!(name: "Dues")
    @alpha_ledger = Ledger.create!(name: "Alpha Fund", team: @alpha)
    @beta_ledger = Ledger.create!(name: "Beta Fund", team: @beta)
    @alpha_dues = create_world_entry(@alpha_ledger, "Dues", 5000, tags: [ @dues ])
    create_world_entry(@alpha_ledger, "Snacks", -1250)
    create_world_entry(@alpha_ledger, "Awaiting payment", 500, finalized: false)
    beta_entry = create_world_entry(@beta_ledger, "Beta dues", 2000, tags: [ @dues ])
    @beta_split = create_world_entry(@beta_ledger, "Half", 1000, parent: beta_entry)
  end

  def with_feature(key, enabled = true, &block)
    with_settings({ "feature_#{key}": enabled.to_s }, &block)
  end

  # Sets Settings values for the duration of a block. Writes go to a
  # throwaway PStore so tests never touch storage/settings.pstore, and the
  # previous values are restored afterwards.
  def with_settings(values)
    restore = apply_settings(values)
    yield
  ensure
    restore&.call
  end

  # Sets Settings values until the returned proc is called, for setups that
  # need them through the whole test (call it in teardown).
  def apply_settings(values)
    settings = Settings.instance
    original_store = settings.store
    path = Rails.root.join("tmp", "test-settings-#{Process.pid}.pstore").to_s
    # Access checks read the store, so nothing a test wrote may reach the next one.
    File.delete(path) if File.exist?(path) && original_store.instance_variable_get(:@filename) != path
    settings.store = PStore.new(path, true)
    previous = values.keys.to_h { |key| [ key, Settings.get(key).instance_variable_get(:@value) ] }
    values.each { |key, value| Settings[key] = value }
    lambda do
      previous.each { |key, value| Settings[key] = value }
      settings.store = original_store
    end
  end

  private

  def create_world_team(name, parent: nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def create_world_person(name, team = nil, manager: false, admin: false)
    user = User.create!(email: "#{name.downcase}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name, last_name: "World")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  def create_world_event(name, team, start_time)
    Event.create!(name: name, team: team, start_time: start_time, end_time: start_time + 1.hour, event_type: event_types(:one))
  end

  def create_world_checkin(person, event)
    Checkin.create!(person: person, event: event)
  end

  def create_world_period(name, team)
    TimeClockPeriod.create!(name: name, team: team, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: :added_by_admin)
  end

  # A punch starting this many hours after March 10 00:00 UTC, open when
  # end_hour is nil.
  def create_world_punch(person, period, start_hour, end_hour)
    base = Time.utc(2026, 3, 10)
    TimeClockPunch.create!(person: person, time_clock_period: period, start_time: base + start_hour.hours,
      end_time: end_hour && base + end_hour.hours, created_by: "kiosk")
  end

  def create_world_entry(ledger, remark, cents, tags: [], finalized: true, parent: nil)
    LedgerEntry.create!(ledger: ledger, remark: remark, amount_cents: cents, finalized: finalized, parent: parent,
      ledger_tags: tags, created_by: person(:admin))
  end

  def create_world_badge(name, team: nil)
    Badge.create!(name: name, short: name.first(3), color: "#336699", badge_type: badge_types(:one), team: team, permission: :added_by_admin)
  end

  # For write tools.

  def create_world_badge_with(permission, team: nil)
    badge = create_world_badge(permission.to_s.humanize, team: team)
    badge.update!(permission: permission)
    badge
  end

  # Asserts the block's call_tool result is this error (a string or regexp) and
  # that it left each model's row count alone.
  def assert_refused(error, *models)
    result = nil
    assert_no_difference(models.map { |model| -> { model.count } }) { result = yield }
    assert_nil result.changed
    error.is_a?(Regexp) ? assert_match(error, result.error.to_s) : assert_equal(error, result.error)
    result
  end

  # Whether the block changes model's row count. The change is rolled back, so the
  # same request can then be tried another way. Works for a page request too: the
  # app runs on the test's thread and database connection.
  def changes_rows?(model)
    changed = false
    model.transaction(requires_new: true) do
      before = model.count
      yield
      changed = model.count != before
      raise ActiveRecord::Rollback
    end
    changed
  end

  # changes_rows? for a page request made as user (needs Devise's integration helpers).
  def page_changes_rows?(model, as:, &block)
    sign_in as
    changes_rows?(model, &block)
  ensure
    sign_out as
  end

  # Gives policy_class this query for the duration of the block, as a build whose
  # policy defines it would have, and puts back whatever was there.
  def with_policy_query(policy_class, query, rule)
    defined_here = policy_class.instance_methods(false).include?(query)
    original = policy_class.instance_method(query) if defined_here
    policy_class.send(:remove_method, query) if defined_here
    policy_class.define_method(query, &rule)
    yield
  ensure
    policy_class.send(:remove_method, query)
    policy_class.define_method(query, original) if original
  end

  # Asserts that the event is in the hook catalog and that a hook on it runs, with
  # the record the block's successful call_tool result says it changed.
  def assert_hook_runs(event)
    assert_includes Hook.catalog, event
    Thread.current[:mcp_hook_model] = nil
    Hook.create!(name: "MCP test hook", event: event, code: "Thread.current[:mcp_hook_model] = model")
    result = yield
    assert_nil result.error
    assert_equal result.changed, Thread.current[:mcp_hook_model]
  ensure
    Thread.current[:mcp_hook_model] = nil
  end
end
