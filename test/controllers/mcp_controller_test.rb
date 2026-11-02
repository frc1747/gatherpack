require "test_helper"
require_relative "../support/mcp_world"

class McpControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  # A test-only write tool: creates a badge assignment, as a later write tool would.
  WRITE_TOOL = Class.new(Mcp::Tool) do
    tool_name "test_assign_badge"
    description "Test write tool"
    scope :write
    input_schema(properties: { person_id: { type: "string" }, badge_id: { type: "string" } }, required: %w[person_id badge_id])

    def call(person_id:, badge_id:)
      assignment = BadgeAssignment.new(person: ctx.find(ctx.policy_scope(Person), person_id), badge: ctx.find(ctx.policy_scope(Badge), badge_id))
      ctx.authorize!(assignment, :create?)
      assignment.save!
      changed!(assignment)
      { id: assignment.neat_id }
    end
  end

  setup do
    host! "localhost"
    build_mcp_world
  end

  def tool_names(body)
    body.dig("result", "tools").map { |tool| tool["name"] }
  end

  # --- Sign-in errors

  test "no token gets 401 with resource_metadata" do
    body = mcp_post(nil, "tools/list")

    assert_response :unauthorized
    assert_equal %(Bearer resource_metadata="http://localhost/.well-known/oauth-protected-resource"), response.headers["WWW-Authenticate"]
    assert_equal "2.0", body["jsonrpc"]
  end

  test "an invalid token gets 401 with invalid_token" do
    post "/mcp", params: {}.to_json, headers: { "Authorization" => "Bearer nonsense", "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], %(error="invalid_token")
    assert_includes response.headers["WWW-Authenticate"], "resource_metadata="
  end

  test "a revoked token gets 401" do
    token = mcp_token(user(:admin))
    token.revoke
    mcp_post(token, "tools/list")

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], %(error="invalid_token")
  end

  test "an expired token gets 401" do
    token = mcp_token(user(:admin))
    token.update!(created_at: 3.hours.ago)
    mcp_post(token, "tools/list")

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], %(error="invalid_token")
  end

  # The test env's null_store can't count, so the store's answer is stubbed.
  test "over the rate limit gets 429, keyed by token" do
    token = mcp_token(user(:admin))
    keys = []
    store = McpController.cache_store
    store.define_singleton_method(:increment) do |key, *, **|
      keys << key
      121
    end
    begin
      body = mcp_post(token, "tools/list")
    ensure
      store.singleton_class.send(:remove_method, :increment)
    end

    assert_response :too_many_requests
    assert_equal "Too many requests", body.dig("error", "message")
    assert_equal [ "rate-limit:mcp:#{token.id}" ], keys
  end

  test "a token with no resource owner gets 401, even with a signed-in session" do
    sign_in user(:admin)
    token = Doorkeeper::AccessToken.create!(resource_owner_id: nil, application_id: mcp_application.id, scopes: "mcp_read mcp_write", expires_in: 2.hours)
    body = mcp_post(token, "tools/list")

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], %(error="invalid_token")
    assert_nil body["result"]
  end

  test "a token in a query parameter isn't accepted" do
    token = mcp_token(user(:admin))
    post "/mcp?access_token=#{token.plaintext_token}", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "a session doesn't stand in for a token" do
    sign_in user(:admin)
    body = mcp_post(nil, "ping")

    assert_response :unauthorized
    assert_nil body["result"]
  end

  test "a token without an MCP scope gets 403 insufficient_scope" do
    mcp_post(mcp_token(user(:admin), scopes: "user_read"), "tools/list")

    assert_response :forbidden
    assert_includes response.headers["WWW-Authenticate"], %(error="insufficient_scope")
    assert_includes response.headers["WWW-Authenticate"], %(scope="mcp_read")
  end

  test "a token gets 403 once its application no longer lists its MCP scopes" do
    token = mcp_token(user(:admin), scopes: "mcp_read mcp_write")
    mcp_post(token, "tools/list")
    assert_response :success

    mcp_application.update!(scopes: "")
    mcp_post(token, "tools/list")

    assert_response :forbidden
    assert_includes response.headers["WWW-Authenticate"], %(error="insufficient_scope")
  end

  test "an application narrowed to mcp_read narrows its tokens at once" do
    token = mcp_token(user(:admin), scopes: "mcp_read mcp_write")
    mcp_application.update!(scopes: "mcp_read")

    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "true") do
        assert_not_includes tool_names(mcp_post(token, "tools/list")), "test_assign_badge"

        assert_no_difference "BadgeAssignment.count" do
          body = mcp_post(token, "tools/call", { name: "test_assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id } })
          assert_equal(-32602, body.dig("error", "code"))
        end

        whoami = mcp_post(token, "tools/call", { name: "whoami" }).dig("result", "structuredContent")
        assert_equal [ "mcp_read" ], whoami["scopes"]
        assert_equal true, whoami["writes_enabled"]
        assert_equal false, whoami["can_write"]
      end
    end
  end

  test "an mcp_read token gets 403 when its application lists only mcp_write" do
    token = mcp_token(user(:admin), scopes: "mcp_read")
    mcp_application.update!(scopes: "mcp_write")
    mcp_post(token, "tools/list")

    assert_response :forbidden
  end

  test "feature off is a 404, whatever the token" do
    with_feature(:mcp, false) do
      mcp_post(mcp_token(user(:admin)), "tools/list")
      assert_response :not_found
      mcp_post(nil, "tools/list")
      assert_response :not_found
    end
  end

  test "a user with no person is refused" do
    orphan = User.create!(email: "orphan@example.com", password: "Password1!")
    body = mcp_post(mcp_token(orphan), "tools/list")

    assert_response :forbidden
    assert_match(/isn't enabled for your account/, body.dig("error", "message"))
  end

  # --- Badge limit

  test "with a badge limit, only holders connect, admins included" do
    with_settings(mcp_allowed_badge: @access_badge.neat_id) do
      mcp_post(mcp_token(user(:badge_holder)), "tools/list")
      assert_response :success

      body = mcp_post(mcp_token(user(:alpha_member)), "tools/list")
      assert_response :forbidden
      assert_match(/isn't enabled for your account/, body.dig("error", "message"))

      mcp_post(mcp_token(user(:admin)), "tools/list")
      assert_response :forbidden
    end
  end

  test "a badge limit naming no badge lets no one in" do
    with_settings(mcp_allowed_badge: "bdg_nonsense") do
      mcp_post(mcp_token(user(:badge_holder)), "tools/list")
      assert_response :forbidden
    end
  end

  # --- Transport

  test "initialize, tools/list and tools/call whoami round trip" do
    token = mcp_token(user(:alpha_member))

    init = mcp_post(token, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "gatherpack", init.dig("result", "serverInfo", "name")
    assert init.dig("result", "capabilities", "tools")
    assert_match(/neat IDs/, init.dig("result", "instructions"))
    assert_nil response.headers["Mcp-Session-Id"]

    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: mcp_headers(token)
    assert_response :accepted

    list = mcp_post(token, "tools/list")
    assert_includes tool_names(list), "whoami"
    whoami = list.dig("result", "tools").find { |tool| tool["name"] == "whoami" }
    assert_equal true, whoami.dig("annotations", "readOnlyHint")
    assert whoami["outputSchema"]

    call = mcp_post(token, "tools/call", { name: "whoami", arguments: {} })
    assert_response :success
    result = call["result"]
    assert_equal false, result["isError"]
    assert_equal person(:alpha_member).neat_id, result.dig("structuredContent", "person", "id")
    assert_equal result["structuredContent"], JSON.parse(result.dig("content", 0, "text"))
  end

  test "a batch is refused: Streamable HTTP takes one message per POST" do
    token = mcp_token(user(:alpha_member))
    post "/mcp", params: [ { jsonrpc: "2.0", id: 1, method: "ping" }, { jsonrpc: "2.0", id: 2, method: "tools/list" } ].to_json,
      headers: mcp_headers(token)

    assert_equal(-32600, response.parsed_body.dig("error", "code"))
  end

  test "an oversized body is refused" do
    token = mcp_token(user(:alpha_member))
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping", params: { pad: "x" * 5.megabytes } }.to_json, headers: mcp_headers(token)

    assert_response :content_too_large
  end

  test "a malformed body is a JSON-RPC parse error" do
    token = mcp_token(user(:alpha_member))
    post "/mcp", params: "{nope", headers: mcp_headers(token)

    assert_equal(-32700, response.parsed_body.dig("error", "code"))
  end

  test "GET and DELETE answer 405" do
    get "/mcp"
    assert_response :method_not_allowed
    assert_equal "POST", response.headers["Allow"]
    delete "/mcp"
    assert_response :method_not_allowed
  end

  test "GET is 404 while the feature is off" do
    with_feature(:mcp, false) do
      get "/mcp"
      assert_response :not_found
    end
  end

  test "another Origin is refused; the app's own and none are allowed" do
    token = mcp_token(user(:alpha_member))

    mcp_post(token, "ping", headers: { "Origin" => "https://evil.example.com" })
    assert_response :forbidden

    mcp_post(token, "ping", headers: { "Origin" => "http://localhost" })
    assert_response :success

    mcp_post(token, "ping")
    assert_response :success
  end

  # --- What a token may list and call

  test "tools/list with mcp_read hides write tools" do
    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "true") do
        assert_not_includes tool_names(mcp_post(mcp_token(user(:admin)), "tools/list")), "test_assign_badge"
      end
    end
  end

  test "tools/list with mcp_write hides write tools while writes are off" do
    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "false") do
        assert_not_includes tool_names(mcp_post(mcp_token(user(:admin), scopes: "mcp_write"), "tools/list")), "test_assign_badge"
      end
      with_settings(mcp_write_enabled: "true") do
        assert_includes tool_names(mcp_post(mcp_token(user(:admin), scopes: "mcp_write"), "tools/list")), "test_assign_badge"
      end
    end
  end

  test "a write tool called with a read token is refused and logged" do
    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "true") do
        assert_no_difference "BadgeAssignment.count" do
          body = mcp_post(mcp_token(user(:admin)), "tools/call",
            { name: "test_assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id } })
          assert_response :success
          assert_equal(-32602, body.dig("error", "code"))
          assert_match(/Tool not found/, body.dig("error", "data"))
        end
        log = McpToolCall.order(:created_at).last
        assert_equal "test_assign_badge", log.tool
        assert_equal "denied", log.outcome
      end
    end
  end

  test "an unknown tool is a protocol error and isn't logged" do
    assert_no_difference "McpToolCall.count" do
      body = mcp_post(mcp_token(user(:admin)), "tools/call", { name: "nope" })
      assert_equal(-32602, body.dig("error", "code"))
      assert_match(/Tool not found/, body.dig("error", "data"))
    end
  end

  test "a write runs as the token's user and logs what it changed" do
    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "true") do
        token = mcp_token(user(:admin), scopes: "mcp_write")
        body = mcp_post(token, "tools/call",
          { name: "test_assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id } })

        assert_equal false, body.dig("result", "isError")
        assignment = BadgeAssignment.find_by!(person: person(:alpha_member), badge: @access_badge)
        version = AuditLog.where(item_type: "BadgeAssignment", item_id: assignment.id).last
        assert_equal user(:admin).id.to_s, version.whodunnit

        log = McpToolCall.order(:created_at).last
        assert_equal "ok", log.outcome
        assert_equal "BadgeAssignment", log.changed_type
        assert_equal assignment.id, log.changed_id
      end
    end
  end

  test "a tool's refusal is a tool result, not a protocol error" do
    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "true") do
        body = mcp_post(mcp_token(user(:alpha_member), scopes: "mcp_write"), "tools/call",
          { name: "test_assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id } })

        assert_equal true, body.dig("result", "isError")
        assert_equal "Not allowed", body.dig("result", "content", 0, "text")
        assert_equal "denied", McpToolCall.order(:created_at).last.outcome
      end
    end
  end

  test "each call logs one row with user, application, tool, arguments and duration" do
    token = mcp_token(user(:alpha_member))

    assert_difference "McpToolCall.count", 1 do
      mcp_post(token, "tools/call", { name: "search_people", arguments: { query: "World" } })
    end

    log = McpToolCall.order(:created_at).last
    assert_equal user(:alpha_member), log.user
    assert_equal mcp_application.id, log.oauth_application_id
    assert_equal "search_people", log.tool
    assert_equal({ "query" => "World" }, log.arguments)
    assert_equal "ok", log.outcome
    assert_not_nil log.duration_ms
  end

  test "tools/list and initialize aren't logged" do
    assert_no_difference "McpToolCall.count" do
      mcp_post(mcp_token(user(:admin)), "tools/list")
    end
  end

  test "invalid arguments come back as a tool error and are logged" do
    body = mcp_post(mcp_token(user(:admin)), "tools/call", { name: "search_people", arguments: {} })

    assert_equal true, body.dig("result", "isError")
    assert_match(/Missing required arguments/, body.dig("result", "content", 0, "text"))
    log = McpToolCall.order(:created_at).last
    assert_equal "error", log.outcome
    assert_match(/Missing required arguments: query/, log.error_message)
  end

  test "a NUL in a junk argument can't keep a call out of the log" do
    with_tool(WRITE_TOOL) do
      with_settings(mcp_write_enabled: "true") do
        assert_difference "McpToolCall.count", 1 do
          assert_no_difference "BadgeAssignment.count" do
            body = mcp_post(mcp_token(user(:admin), scopes: "mcp_write"), "tools/call",
              { name: "test_assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id, note: "\u0000" } })
            assert_equal true, body.dig("result", "isError")
          end
        end
      end
    end
  end

  test "a large junk argument isn't stored" do
    assert_difference "McpToolCall.count", 1 do
      mcp_post(mcp_token(user(:admin)), "tools/call", { name: "whoami", arguments: { junk: "x" * 100_000 } })
    end

    assert_response :success
    assert_equal({}, McpToolCall.order(:created_at).last.arguments)
  end

  test "a tool bug over HTTP is a generic internal error" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_http_bug"
      description "Test tool"
      scope :read
      define_method(:call) { { rows: ctx.policy_scope(Checkin).count } }
    end
    with_tool(tool) do
      body = mcp_post(mcp_token(user(:admin)), "tools/call", { name: "test_http_bug" })

      assert_equal(-32603, body.dig("error", "code"))
      assert_not_includes response.body, "CheckinPolicy"
      assert_equal "error", McpToolCall.order(:created_at).last.outcome
    end
  end

  test "a call whose schema check fails is logged once" do
    assert_difference "McpToolCall.count", 1 do
      body = mcp_post(mcp_token(user(:admin)), "tools/call", { name: "search_people", arguments: { query: "a", limit: 0 } })
      assert_equal true, body.dig("result", "isError")
    end
  end

  test "an unexpected exception returns no details" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_boom"
      description "Test tool"
      scope :read
      define_method(:call) { raise "secret detail" }
    end
    with_tool(tool) do
      body = mcp_post(mcp_token(user(:admin)), "tools/call", { name: "test_boom" })

      assert_equal "Internal error", body.dig("result", "content", 0, "text")
      assert_not_includes response.body, "secret"
    end
  end

  # --- Core write tools

  WRITE_TOOLS = %w[assign_badge remove_badge add_team_member remove_team_member record_checkin create_event].freeze

  test "tools/list shows the write tools only with mcp_write and mcp_write_enabled" do
    read = mcp_token(user(:admin))
    write = mcp_token(user(:admin), scopes: "mcp_write")

    with_settings(mcp_write_enabled: "true") do
      assert_empty WRITE_TOOLS & tool_names(mcp_post(read, "tools/list"))
      listed = mcp_post(write, "tools/list").dig("result", "tools")
      assert_empty WRITE_TOOLS - listed.map { |tool| tool["name"] }

      hints = listed.select { |tool| WRITE_TOOLS.include?(tool["name"]) }.to_h { |tool| [ tool["name"], tool.dig("annotations", "destructiveHint") ] }
      assert_equal %w[remove_badge remove_team_member], hints.select { |_name, hint| hint }.keys
    end
    with_settings(mcp_write_enabled: "false") do
      assert_empty WRITE_TOOLS & tool_names(mcp_post(write, "tools/list"))
    end
  end

  test "a token with mcp_write issued while writes were on gets no write tools once they're off" do
    token = with_settings(mcp_write_enabled: "true") { mcp_token(user(:admin), scopes: "mcp_read mcp_write") }

    with_settings(mcp_write_enabled: "false") do
      assert_empty WRITE_TOOLS & tool_names(mcp_post(token, "tools/list"))
      assert_no_difference -> { BadgeAssignment.count } do
        body = mcp_post(token, "tools/call", { name: "assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id } })

        assert body.key?("error")
      end
    end
  end

  test "assign_badge runs as the token's user and logs the assignment" do
    with_settings(mcp_write_enabled: "true") do
      body = mcp_post(mcp_token(user(:admin), scopes: "mcp_write"), "tools/call",
        { name: "assign_badge", arguments: { person_id: person(:alpha_member).neat_id, badge_id: @access_badge.neat_id } })

      assert_equal false, body.dig("result", "isError")
      assignment = BadgeAssignment.find_by!(person: person(:alpha_member), badge: @access_badge)
      assert_equal assignment.neat_id, body.dig("result", "structuredContent", "id")
      assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "BadgeAssignment", item_id: assignment.id).last.whodunnit

      log = McpToolCall.order(:created_at).last
      assert_equal [ "assign_badge", "ok", "BadgeAssignment", assignment.id ], [ log.tool, log.outcome, log.changed_type, log.changed_id ]
    end
  end

  test "remove_team_member runs as the token's user and logs the membership" do
    membership = Membership.find_by!(person: person(:alpha_member), team: @alpha)

    with_settings(mcp_write_enabled: "true") do
      body = mcp_post(mcp_token(user(:alpha_manager), scopes: "mcp_write"), "tools/call",
        { name: "remove_team_member", arguments: { membership_id: membership.neat_id } })

      assert_equal false, body.dig("result", "isError")
      assert_not Membership.exists?(membership.id)
      version = AuditLog.where(item_type: "Membership", item_id: membership.id, event: "destroy").last
      assert_equal user(:alpha_manager).id.to_s, version.whodunnit

      log = McpToolCall.order(:created_at).last
      assert_equal [ "Membership", membership.id ], [ log.changed_type, log.changed_id ]
    end
  end

  test "tools run in the app's time zone" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_zone"
      description "Test tool"
      scope :read
      define_method(:call) { { zone: Time.zone.name } }
    end
    with_tool(tool) do
      with_settings(time_zone: "America/Detroit") do
        body = mcp_post(mcp_token(user(:admin)), "tools/call", { name: "test_zone" })
        assert_equal "America/Detroit", body.dig("result", "structuredContent", "zone")
      end
    end
  end
end
