require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RecordCheckinTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    meeting = Time.utc(2026, 3, 10, 18, 0)
    @alpha_event = create_world_event("Alpha Meeting", @alpha, meeting)
    @beta_event = create_world_event("Beta Meeting", @beta, meeting)
    @open_event = create_world_event("Open Day", nil, meeting)
    @locked_event = create_world_event("Locked Meeting", @alpha, meeting)
    @locked_event.update!(locked: true)
  end

  def check_in(viewer, attendee, event, **options)
    call_tool("record_checkin", user: user(viewer), person_id: person(attendee).neat_id, event_id: event.neat_id, **options)
  end

  test "an admin checks anyone in to any event and gets the check-in back" do
    result = check_in(:admin, :beta_member, @open_event)

    checkin = Checkin.find_by!(person: person(:beta_member), event: @open_event)
    assert_equal checkin, result.changed
    assert_equal checkin.neat_id, result.value["id"]
    assert_equal person(:beta_member).neat_id, result.value.dig("person", "id")
    assert_equal @open_event.neat_id, result.value.dig("event", "id")
  end

  test "it sets created_by to the viewer, as the page does" do
    assert_equal person(:alpha_manager), check_in(:alpha_manager, :ward, @alpha_event).changed.created_by
  end

  test "a team manager checks in on their team's events, locked ones too" do
    assert_nil check_in(:alpha_manager, :alpha_member, @alpha_event).error
    assert_nil check_in(:alpha_manager, :alpha_member, @locked_event).error
  end

  test "a plain member checks in only themselves, and not on a locked event" do
    assert_refused("Not allowed", Checkin) { check_in(:alpha_member, :ward, @alpha_event) }
    assert_nil check_in(:alpha_member, :alpha_member, @alpha_event).error
    assert_refused("Not allowed", Checkin) { check_in(:alpha_member, :alpha_member, @locked_event) }
  end

  test "a plain member on another team can't reach the event or the person" do
    assert_refused("Not found", Checkin) { check_in(:beta_member, :beta_member, @alpha_event) }
    assert_refused("Not found", Checkin) { check_in(:beta_member, :alpha_member, @beta_event) }
  end

  test "non-admins can't reach a team-less event" do
    assert_refused("Not found", Checkin) { check_in(:alpha_manager, :alpha_manager, @open_event) }
  end

  test "a guardian can't reach the event or their ward" do
    assert_refused("Not found", Checkin) { check_in(:guardian, :guardian, @alpha_event) }
    assert_refused("Not found", Checkin) { check_in(:guardian, :ward, @alpha_event) }
  end

  test "the check-in limit returns the validation message" do
    @alpha_event.update!(checkin_limit: 1)
    assert_nil check_in(:admin, :alpha_member, @alpha_event).error

    assert_refused(/exceeds checkin limit/, Checkin) { check_in(:admin, :ward, @alpha_event) }
  end

  test "a duplicate returns the validation message" do
    check_in(:admin, :ward, @alpha_event)

    assert_refused("Person has already been checked in", Checkin) { check_in(:admin, :ward, @alpha_event) }
  end

  test "an event type's check-in fields get blank responses, as an empty form does" do
    field = CheckinField.create!(name: "Note", event_type: @alpha_event.event_type)

    result = check_in(:alpha_member, :alpha_member, @alpha_event)

    assert_nil result.error
    response = result.changed.checkin_field_responses.find_by!(checkin_field: field)
    assert_nil response.response
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "evt_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", Checkin) { call_tool("record_checkin", user: user(:admin), person_id: person(:ward).neat_id, event_id: bad) }
      assert_refused("Not found", Checkin) { call_tool("record_checkin", user: user(:admin), person_id: bad, event_id: @alpha_event.neat_id) }
    end
    assert_refused(/event_id/, Checkin) { call_tool("record_checkin", user: user(:admin), person_id: person(:ward).neat_id) }
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_refused("Not allowed", Checkin) { check_in(:admin, :ward, @alpha_event, scopes: "mcp_read") }
    assert_refused("Writes disabled", Checkin) { check_in(:admin, :ward, @alpha_event, writes_enabled: false) }
    with_feature(:events, false) { assert_refused("Feature off", Checkin) { check_in(:admin, :ward, @alpha_event) } }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("checkins - create") { check_in(:admin, :ward, @alpha_event) }
  end

  test "it allows and refuses as the page does" do
    limited = create_world_event("Limited", @alpha, Time.utc(2026, 3, 10, 18, 0))
    limited.update!(checkin_limit: 1)
    create_world_checkin(person(:alpha_member), limited)
    [
      [ :admin, :beta_member, @open_event ],
      [ :admin, :ward, limited ],
      [ :alpha_manager, :ward, @locked_event ],
      [ :alpha_manager, :ward, @open_event ],
      [ :alpha_member, :ward, @alpha_event ],
      [ :alpha_member, :alpha_member, @locked_event ],
      [ :beta_member, :beta_member, @alpha_event ],
      [ :beta_member, :beta_member, @beta_event ],
      [ :guardian, :guardian, @alpha_event ],
      [ :guardian, :ward, @alpha_event ]
    ].each do |viewer, attendee, event|
      page = page_changes_rows?(Checkin, as: user(viewer)) do
        post event_checkins_path(event), params: { checkin: { person_id: person(attendee).id } }
      end
      tool = changes_rows?(Checkin) { check_in(viewer, attendee, event) }

      assert_equal page, tool, "#{viewer} checking #{attendee} in to #{event.name}"
    end
  end

  # This build's POST checks the person too.
  test "it refuses a person the viewer can't see, and so does a hand-made POST" do
    page = page_changes_rows?(Checkin, as: user(:alpha_member)) do
      post event_checkins_path(@alpha_event), params: { checkin: { person_id: person(:beta_member).id } }
    end

    assert_not page
    assert_refused("Not found", Checkin) { check_in(:alpha_member, :beta_member, @alpha_event) }
  end
end
