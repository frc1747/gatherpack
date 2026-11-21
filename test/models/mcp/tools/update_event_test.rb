require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::UpdateEventTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
  end

  def update(viewer, event = @alpha_event, **changes)
    call_tool("update_event", user: user(viewer), event_id: event.neat_id, **changes)
  end

  def assert_unchanged(error, event = @alpha_event)
    before = event.reload.attributes
    assert_refused(error, AuditLog) { yield }
    assert_equal before, event.reload.attributes
  end

  test "an admin changes every attribute, and only those, and gets the event back as get_event shows it" do
    other_type = event_types(:two)
    value = update(:admin, name: "Renamed", description: "About", starts_at: "2026-03-10T19:00:00Z", ends_at: "2026-03-10T21:00:00Z",
      location: "Hall", event_type_id: other_type.neat_id, team_id: @beta.neat_id, locked: true,
      time_clock_period_id: @beta_period.neat_id, checkin_limit: 40).value

    @alpha_event.reload
    assert_equal [ "Renamed", "About", "Hall", other_type, @beta, true, @beta_period, 40 ],
      [ @alpha_event.name, @alpha_event.description, @alpha_event.location, @alpha_event.event_type, @alpha_event.team, @alpha_event.locked, @alpha_event.time_clock_period, @alpha_event.checkin_limit ]
    assert_equal Time.utc(2026, 3, 10, 19), @alpha_event.start_time
    assert_equal Time.utc(2026, 3, 10, 21), @alpha_event.end_time

    shown = call_tool("get_event", user: user(:admin), event_id: @alpha_event.neat_id).value
    assert_equal shown, value.except("locked", "time_clock_period")
    assert_equal true, value["locked"]
    assert_equal @beta_period.neat_id, value.dig("time_clock_period", "id")
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Event", item_id: @alpha_event.id, event: "update").last.whodunnit
  end

  test "a partial change leaves the rest alone, and null clears what the form can blank" do
    @alpha_event.update!(description: "About", location: "Hall", checkin_limit: 5, time_clock_period: @alpha_period)
    before = @alpha_event.reload.attributes

    assert_nil update(:alpha_manager, name: "Renamed").error
    assert_equal before.except("name", "updated_at"), @alpha_event.reload.attributes.except("name", "updated_at")

    value = update(:alpha_manager, description: nil, location: nil, ends_at: nil, checkin_limit: nil, time_clock_period_id: nil).value
    assert_equal [ nil, nil, nil, nil ], value.values_at("description", "location", "end_time", "checkin_limit")
    assert_nil value["time_clock_period"]
    assert_nil @alpha_event.reload.time_clock_period
  end

  test "a team manager moves it to a team they manage, not one they don't, and can't leave it team-less" do
    child = create_world_team("Alpha Child", parent: @alpha)
    @beta.update!(join_permission: :has_account)

    assert_unchanged("Not allowed") { update(:alpha_manager, team_id: @beta.neat_id) }
    assert_unchanged("Not allowed") { update(:alpha_manager, team_id: nil) }
    assert_equal child.neat_id, update(:alpha_manager, team_id: child.neat_id).value.dig("team", "id")
  end

  test "a team hidden from the viewer is not found, and an admin can leave it team-less" do
    assert_unchanged("Not found") { update(:alpha_manager, team_id: @beta.neat_id) }
    assert_nil update(:admin, team_id: nil).value["team"]
  end

  test "a plain member can see it but not edit it" do
    assert_unchanged("Not allowed") { update(:alpha_member, name: "Nope") }
  end

  test "a member on another team, a guardian, and anyone but an admin on a team-less event can't reach it" do
    assert_unchanged("Not found") { update(:beta_member, name: "Nope") }
    assert_unchanged("Not found") { update(:guardian, name: "Nope") }
    assert_unchanged("Not found", @open_event) { update(:alpha_manager, @open_event, name: "Nope") }
  end

  test "a read token, the setting being off and a bad ID refuse it" do
    assert_unchanged("Not allowed") { update(:admin, name: "Nope", scopes: "mcp_read") }
    assert_unchanged("Writes disabled") { update(:admin, name: "Nope", writes_enabled: false) }
    assert_equal "Not found", call_tool("update_event", user: user(:admin), event_id: @alpha_event.id, name: "Nope").error
  end

  test "another period the viewer can't see is not found, and their event's own period can be named again" do
    @alpha_event.update_column(:time_clock_period_id, @beta_period.id) # An event from before the period had to match its team.

    assert_nil update(:alpha_manager, name: "Renamed", time_clock_period_id: @beta_period.neat_id).error
    assert_equal @beta_period, @alpha_event.reload.time_clock_period
    @alpha_event.update!(time_clock_period: @alpha_period)
    assert_unchanged("Not found") { update(:alpha_manager, time_clock_period_id: @beta_period.neat_id) }
  end

  test "nothing to change, or an argument it doesn't take, is refused rather than dropped" do
    assert_unchanged(/Give at least one/) { update(:admin) }
    assert_unchanged(/start_time/) { update(:admin, start_time: "2026-03-10T19:00:00Z") }
  end

  test "bad values are refused by name, and the model's validations come back" do
    [ { starts_at: "soon" }, { starts_at: "2026-02-31T18:00:00" }, { ends_at: "2026-03-10" }, { starts_at: nil }, { name: nil }, { locked: "no" },
      { checkin_limit: 2_147_483_648 }, { checkin_limit: Float::INFINITY }, { checkin_limit: 1.5 }, { name: "a\nb" }, { location: "a\u0007b" } ].each do |changes|
      assert_unchanged(/#{changes.keys.first}|number/) { update(:admin, **changes) }
    end
    assert_unchanged(/before start time/) { update(:admin, ends_at: "2026-03-01T00:00:00Z") }
    assert_unchanged(/Name can't be blank/) { update(:admin, name: "") }
  end

  test "it saves through the model, so callbacks and hooks run as on the page" do
    assert_hook_runs("events - update") { update(:admin, starts_at: "2026-03-10T19:00:00Z") }

    called = []
    Event.set_callback(:update, :after, recorder = ->(event) { called << event.id })
    begin
      update(:admin, name: "Renamed")
    ensure
      Event.skip_callback(:update, :after, recorder)
    end
    assert_equal [ @alpha_event.id ], called
  end

  test "changing nothing reports no change" do
    result = with_settings(mcp_write_enabled: "true") { Mcp.tool("update_event").run(mcp_context(user(:admin), scopes: "mcp_write"), { event_id: @alpha_event.neat_id, name: @alpha_event.name }) }

    assert_nil result.error
    assert_nil result.changed
  end

  test "it allows and refuses as the page does" do
    [ [ :admin, true ], [ :alpha_manager, true ], [ :alpha_member, false ], [ :beta_member, false ], [ :guardian, false ] ].each do |viewer, allowed|
      sign_in user(viewer)
      patch event_path(@alpha_event), params: { event: { name: "From the page" } }
      sign_out user(viewer)
      assert_equal allowed, @alpha_event.reload.name == "From the page", "#{viewer} on the page"
      @alpha_event.update!(name: "Alpha Meeting")

      update(viewer, name: "From the tool")
      assert_equal allowed, @alpha_event.reload.name == "From the tool", "#{viewer} with the tool"
      @alpha_event.update!(name: "Alpha Meeting")
    end
  end
end
