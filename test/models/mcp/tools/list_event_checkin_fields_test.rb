require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListEventCheckinFieldsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    @type = EventType.create!(name: "With fields")
    @event = create_world_event("Alpha Meeting", @alpha, Time.utc(2026, 3, 10, 18))
    @event.update!(event_type: @type)
    @open_event = create_world_event("Open Day", nil, Time.utc(2026, 3, 11, 18))
    @shirt = CheckinField.create!(event_type: @type, name: "Shirt", permission: :added_by_user)
    @notes = CheckinField.create!(event_type: @type, name: "Notes", permission: :added_by_manager)
    CheckinField.create!(event_type: event_types(:two), name: "Other type's")
  end

  def fields(viewer, event = @event, **options)
    call_tool("list_event_checkin_fields", user: user(viewer), event_id: event.neat_id, **options)
  end

  test "an admin, a team manager and a member get the event type's fields, by name" do
    %i[admin alpha_manager alpha_member].each do |viewer|
      assert_equal({
        "items" => [
          { "id" => @notes.neat_id, "name" => "Notes", "permission" => "added_by_manager" },
          { "id" => @shirt.neat_id, "name" => "Shirt", "permission" => "added_by_user" }
        ],
        "truncated" => false
      }, fields(viewer).value, viewer)
    end
  end

  test "a plain member on another team and a guardian get not found" do
    assert_equal "Not found", fields(:beta_member).error
    assert_equal "Not found", fields(:guardian).error
  end

  test "a team-less event is out of a non-admin's scope, as on the events index" do
    assert_nil fields(:admin, @open_event).error
    assert_equal "Not found", fields(:alpha_member, @open_event).error
  end

  test "nobody's answers come back" do
    checkin = create_world_checkin(person(:alpha_member), @event)
    checkin.checkin_field_responses.find_by!(checkin_field: @shirt).update!(response: "Large")

    assert_not_includes fields(:admin).value.to_json, "Large"
  end

  test "limit truncates, invalid IDs are not found, and the feature being off refuses it" do
    assert fields(:admin, limit: 1).value["truncated"]
    assert_equal "Not found", call_tool("list_event_checkin_fields", user: user(:admin), event_id: "evt_nonsense").error
    with_feature(:events, false) { assert_equal "Feature off", fields(:admin).error }
  end
end
