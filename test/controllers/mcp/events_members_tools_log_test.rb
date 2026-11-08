require "test_helper"
require_relative "../../support/mcp_world"

# Over the real /mcp endpoint: what a check-in's notes and answers leave in the Rails log, at the
# production level.
class Mcp::EventsMembersToolsLogTest < ActionDispatch::IntegrationTest
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @type = EventType.create!(name: "With fields")
    @field = CheckinField.create!(event_type: @type, name: "Open", permission: :added_by_user)
    @alpha_event.update!(event_type: @type)
    @checkin = Checkin.find_by!(person: person(:ward), event: @alpha_event)
  end

  def log_of(arguments, viewer: :admin)
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    with_settings(mcp_write_enabled: "true") do
      @response_body = mcp_post(mcp_token(user(viewer), scopes: "mcp_read mcp_write"), "tools/call", { name: "update_checkin", arguments: arguments })
    end
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "notes and answers aren't in the log, stored or refused" do
    log = log_of({ checkin_id: @checkin.neat_id, notes: "Notesecret", field_responses: { @field.neat_id => "Answersecret" } })

    assert_equal "Notesecret", @checkin.reload.notes
    assert_includes log, "Parameters"
    assert_includes log, @checkin.neat_id
    assert_not_includes log, "Notesecret"
    assert_not_includes log, "Answersecret"

    log = log_of({ checkin_id: @checkin.neat_id, notes: "Refusedsecret", field_responses: { @field.neat_id => "Refusedanswer" } }, viewer: :beta_member)
    assert_not_includes log, "Refusedsecret"
    assert_not_includes log, "Refusedanswer"
  end

  test "what's sent under another name isn't in the log either, though it's refused" do
    log = log_of({ checkin_id: @checkin.neat_id, responses: { @field.neat_id => "Secret1" }, response: "Secret2", answers: { @field.neat_id => "Secret3" }, note: "Secret4" })

    assert_includes @response_body.to_json, "isError"
    %w[Secret1 Secret2 Secret3 Secret4].each { |value| assert_not_includes log, value }
  end

  test "so are the near-misses: the model's and the page's own names for answers" do
    log = log_of({ checkin_id: @checkin.neat_id, answer: "Secret1", checkin_field_responses: "Secret2", checkin_field_responses_attributes: { "0" => { response: "Secret3" } }, fields: { @field.neat_id => "Secret4" } })

    assert_includes @response_body.to_json, "isError"
    assert_includes log, @checkin.neat_id
    %w[Secret1 Secret2 Secret3 Secret4].each { |value| assert_not_includes log, value }
  end

  test "the new tools are listed for a write token, and only the reads for a read one" do
    new_tools = %w[update_team_member list_membership_applications decide_membership_application withdraw_membership_application update_event remove_event remove_checkin update_checkin list_relationship_types add_relationship remove_relationship]
    with_settings(mcp_write_enabled: "true") do
      write_tools = mcp_post(mcp_token(user(:admin), scopes: "mcp_read mcp_write"), "tools/list").dig("result", "tools").map { |tool| tool["name"] }
      read_tools = mcp_post(mcp_token(user(:admin)), "tools/list").dig("result", "tools").map { |tool| tool["name"] }

      assert_empty new_tools - write_tools
      assert_equal %w[list_membership_applications list_relationship_types], new_tools & read_tools
    end
  end
end
