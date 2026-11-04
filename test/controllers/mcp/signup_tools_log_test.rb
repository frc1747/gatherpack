require "test_helper"
require_relative "../../support/mcp_world"
require_relative "../../support/mcp_signups_world"

# Over the real /mcp endpoint: what a sign-up tool's arguments leave in the Rails log,
# at the production level.
class Mcp::SignupToolsLogTest < ActionDispatch::IntegrationTest
  include McpWorld
  include McpSignupsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
    @sheet.update!(cancel_cutoff_hours: 24)
  end

  def logged_line_for(viewer, arguments)
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    with_settings(mcp_write_enabled: "true") do
      mcp_post(mcp_token(user(viewer), scopes: "mcp_read mcp_write"), "tools/call", { name: "update_signup", arguments: arguments })
    end
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "an answer and a note aren't in the log when stored, and the IDs still are" do
    log = logged_line_for(:organizer, { signup_id: @ward_cookies.neat_id, answer: "Answersecret", note: "Notesecret" })

    assert_equal "Notesecret", @ward_cookies.reload.note
    assert_includes log, "Parameters"
    assert_includes log, "[FILTERED]"
    %w[Answersecret Notesecret].each { |value| assert_not_includes log, value }
    assert_includes log, @ward_cookies.neat_id
  end

  test "an answer and a note aren't in the log when refused, by permission or by the closed schema" do
    log = logged_line_for(:alpha_plain, { signup_id: @ward_cookies.neat_id, answer: "Answersecret", note: "Notesecret" })
    %w[Answersecret Notesecret].each { |value| assert_not_includes log, value }

    log = logged_line_for(:admin, { signup_id: @ward_cookies.neat_id, answer: "Answersecret", note: "Notesecret", signup_slot_id: "susl_1" })
    %w[Answersecret Notesecret].each { |value| assert_not_includes log, value }
    assert_nil @ward_cookies.reload.note
  end
end
