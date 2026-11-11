require "test_helper"
require_relative "../../support/mcp_world"

# Over the real /mcp endpoint: what the time clock and token tools' arguments leave in the
# Rails log, at the production level.
class Mcp::TimeTokenToolsLogTest < ActionDispatch::IntegrationTest
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def log_of(tool, arguments, viewer: :admin)
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    with_settings(mcp_write_enabled: "true") do
      @response_body = mcp_post(mcp_token(user(viewer), scopes: "mcp_read mcp_write"), "tools/call", { name: tool, arguments: arguments })
    end
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "a token's value isn't in the log or the response, stored or refused" do
    log = log_of("add_token", { person_id: person(:ward).neat_id, value: "170000000034" })

    assert_equal "170000000034", Token.find_by!(tokenable: person(:ward)).value
    assert_includes log, "Parameters"
    assert_includes log, "[FILTERED]"
    assert_includes log, person(:ward).neat_id
    assert_not_includes log, "170000000034"
    assert_not_includes @response_body.to_json, "170000000034"
    assert_includes @response_body.to_json, "17••••••••34"

    log = log_of("add_token", { person_id: person(:ward).neat_id, value: "990000000011" }, viewer: :alpha_member)
    assert_not_includes log, "990000000011"

    log = log_of("add_token", { person_id: person(:ward).neat_id, value: "770000000011", extra: "x" })
    assert_not_includes log, "770000000011"
  end

  test "a value sent under another name isn't in the log either, though it's refused" do
    log = log_of("add_token", { person_id: person(:ward).neat_id, value: "660000000011", token_value: "550000000044", rfid: "440000000055", card: "330000000066", card_number: "220000000077", token: "110000000088" })

    assert_includes @response_body.to_json, "isError"
    %w[660000000011 550000000044 440000000055 330000000066 220000000077 110000000088].each { |value| assert_not_includes log, value }
    assert_includes log, person(:ward).neat_id
  end

  test "a punch's note isn't in the log, stored or refused" do
    arguments = { person_id: person(:ward).neat_id, starts_at: "2026-03-11T18:00:00", note: "Notesecret" }

    log = log_of("record_punch", arguments)
    assert TimeClockPunch.exists?(note: "Notesecret")
    assert_not_includes log, "Notesecret"
    assert_includes log, person(:ward).neat_id

    assert_not_includes log_of("record_punch", arguments.merge(person_id: person(:alpha_member).neat_id), viewer: :ward), "Notesecret"
    punch = TimeClockPunch.find_by!(note: "Notesecret")
    assert_not_includes log_of("update_punch", { punch_id: punch.neat_id, note: "Notesecret2" }), "Notesecret2"
  end

  test "the new tools are listed for a write token, and only the reads for a read one" do
    new_tools = %w[list_time_clock_periods list_punches record_punch update_punch remove_punch clock_out list_tokens add_token remove_token]
    with_settings(mcp_write_enabled: "true") do
      write_tools = mcp_post(mcp_token(user(:admin), scopes: "mcp_read mcp_write"), "tools/list").dig("result", "tools").map { |tool| tool["name"] }
      read_tools = mcp_post(mcp_token(user(:admin)), "tools/list").dig("result", "tools").map { |tool| tool["name"] }

      assert_empty new_tools - write_tools
      assert_equal %w[list_time_clock_periods list_punches list_tokens], new_tools & read_tools
    end
  end
end
