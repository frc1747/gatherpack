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
#   call_tool("search_people", user: user(:admin), query: "World")  # => Mcp::Tool::Result
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
  # call log) and returns its Mcp::Tool::Result. A successful result is
  # checked against the tool's output schema.
  def call_tool(name, user:, scopes: "mcp_read", **arguments)
    tool = Mcp.tool(name) || flunk("No MCP tool #{name}")
    result = tool.run(mcp_context(user, scopes: scopes), arguments)
    if !result.error? && tool.output_schema
      MCP::Tool::OutputSchema.new(tool.output_schema).validate_result(result.value)
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
    settings.store = PStore.new(Rails.root.join("tmp", "test-settings-#{Process.pid}.pstore").to_s)
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

  def create_world_badge(name, team: nil)
    Badge.create!(name: name, short: name.first(3), color: "#336699", badge_type: badge_types(:one), team: team, permission: :added_by_admin)
  end
end
