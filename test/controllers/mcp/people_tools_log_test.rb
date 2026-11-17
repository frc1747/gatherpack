require "test_helper"
require_relative "../../support/mcp_world"

# Over the real /mcp endpoint: what a people tool's arguments leave in the Rails log,
# at the production level.
class Mcp::PeopleToolsLogTest < ActionDispatch::IntegrationTest
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def logged_line_for(tool, arguments, viewer: :admin)
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    with_settings(mcp_write_enabled: "true") do
      mcp_post(mcp_token(user(viewer), scopes: "mcp_read mcp_write"), "tools/call", { name: tool, arguments: arguments })
    end
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "create_person's details, stored and refused, aren't in the log; the password isn't either" do
    original = Devise.method(:friendly_token)
    Devise.define_singleton_method(:friendly_token) { |_length = 20| "secret-generated-password-value" }
    begin
      log = logged_line_for("create_person", { first_name: "Firstsecret", last_name: "Lastsecret", display_name: "Displaysecret", email: "emailsecret@example.com" })

      assert_includes log, "Parameters"
      assert_includes log, "[FILTERED]"
      %w[Firstsecret Lastsecret Displaysecret emailsecret secret-generated].each { |value| assert_not_includes log, value }
    ensure
      Devise.define_singleton_method(:friendly_token, original)
    end
    assert User.exists?(email: "emailsecret@example.com")

    log = logged_line_for("create_person", { first_name: "Firstsecret", last_name: "Lastsecret", password: "client-sent", phone_number: "555-0100", birthday: "2015-01-01", address: "1 Secret St",
      gender: "GENDERSECRET", shirt_size: "SHIRTSECRET", dietary_restrictions: "DIETSECRET" }, viewer: :beta_member)
    %w[Firstsecret client-sent 555-0100 2015-01-01 Secret GENDERSECRET SHIRTSECRET DIETSECRET].each { |value| assert_not_includes log, value }
  end

  test "a client's 1e400 over the real endpoint is a refusal, not an internal error" do
    body = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "find_duplicate_people", arguments: { first_name: "A", last_name: "B" } } }.to_json
    post "/mcp", params: body.sub('"last_name":"B"', '"last_name":"B","limit":1e400'), headers: mcp_headers(mcp_token(user(:admin)))

    result = response.parsed_body["result"]
    assert_equal true, result["isError"]
    assert_equal "limit is out of range", result["content"].first["text"]
    assert_equal "error", McpToolCall.order(:created_at).last.outcome
  end

  test "update_person's details aren't in the log, and the IDs still are" do
    log = logged_line_for("update_person", { person_id: person(:ward).neat_id, bio: "Biosecret", first_name: "Firstsecret", email: "emailsecret@example.com" })

    %w[Biosecret Firstsecret emailsecret].each { |value| assert_not_includes log, value }
    assert_includes log, person(:ward).neat_id
  end

  test "add_login's and find_duplicate_people's aren't either" do
    login_less = Person.create!(first_name: "No", last_name: "Login")
    log = logged_line_for("add_login", { person_id: login_less.neat_id, email: "emailsecret@example.com" })
    assert_not_includes log, "emailsecret"

    log = logged_line_for("find_duplicate_people", { first_name: "Firstsecret", last_name: "Lastsecret", email: "emailsecret@example.com" })
    %w[Firstsecret Lastsecret emailsecret].each { |value| assert_not_includes log, value }
  end

  test "the instructions say a refusal means the member can't do it on the site either" do
    body = mcp_post(mcp_token(user(:admin)), "initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "test", version: "1" } })

    assert_includes body.dig("result", "instructions"), "Changes need the member's own permission. If a change is refused, the member can't make it on the site either."
  end

  test "the new tools are listed for a write token, and only find_duplicate_people for a read one" do
    new_tools = %w[create_person update_person add_login find_duplicate_people]
    with_settings(mcp_write_enabled: "true") do
      write_tools = mcp_post(mcp_token(user(:admin), scopes: "mcp_read mcp_write"), "tools/list").dig("result", "tools").map { |tool| tool["name"] }
      read_tools = mcp_post(mcp_token(user(:admin)), "tools/list").dig("result", "tools").map { |tool| tool["name"] }

      assert_empty new_tools - write_tools
      assert_equal %w[find_duplicate_people], new_tools & read_tools
    end
  end
end
