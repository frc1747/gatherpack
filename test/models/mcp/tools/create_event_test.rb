require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::CreateEventTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  STARTS = "2026-03-10T18:00:00".freeze
  ENDS = "2026-03-10T19:30:00".freeze

  setup do
    host! "localhost"
    build_mcp_world
    @open_team = create_world_team("Open")
    @open_team.update!(join_permission: :has_account)
    @child = create_world_team("Alpha Child", parent: @alpha)
  end

  def create_event(viewer, team = @alpha, **options)
    call_tool("create_event", user: user(viewer), team_id: team.neat_id, event_type_id: event_types(:one).neat_id,
      name: "Planning", starts_at: STARTS, ends_at: ENDS, **options)
  end

  test "an admin creates an event for any team and gets it back" do
    result = create_event(:admin, @beta, location: "Gym")

    event = Event.find_by!(name: "Planning")
    assert_equal event, result.changed
    assert_equal [ @beta, event_types(:one), "Gym" ], [ event.team, event.event_type, event.location ]
    assert_equal [ event.neat_id, "Planning", "Gym" ], result.value.values_at("id", "name", "location")
    assert_equal @beta.neat_id, result.value.dig("team", "id")
    assert_equal event_types(:one).neat_id, result.value.dig("event_type", "id")
  end

  test "a time without an offset is in the app's time zone; one with an offset keeps its instant" do
    with_settings(time_zone: "America/Detroit") do
      result = create_event(:admin, ends_at: "2026-03-10T23:30:00Z")

      assert_equal Time.utc(2026, 3, 10, 22, 0), result.changed.start_time
      assert_equal Time.utc(2026, 3, 10, 23, 30), result.changed.end_time
      assert_equal "2026-03-10T18:00:00-04:00", result.value["start_time"]
    end
  end

  test "a team manager creates events for their team and child teams" do
    assert_difference("Event.count", 2) do
      assert_nil create_event(:alpha_manager).error
      assert_nil create_event(:alpha_manager, @child).error
    end
  end

  test "a manager can't create events for a team they don't manage" do
    assert_refused("Not found", Event) { create_event(:alpha_manager, @beta) }
    assert_refused("Not allowed", Event) { create_event(:alpha_manager, @open_team) }
  end

  test "a plain member can't create events, on their own team or another" do
    assert_refused("Not allowed", Event) { create_event(:beta_member, @beta) }
    assert_refused("Not found", Event) { create_event(:beta_member, @alpha) }
  end

  test "a guardian can't create events for their ward's team" do
    assert_refused("Not found", Event) { create_event(:guardian) }
    assert_refused("Not allowed", Event) { create_event(:guardian, @open_team) }
  end

  test "a refusal comes before any complaint about the times" do
    assert_refused("Not allowed", Event) { create_event(:beta_member, @beta, starts_at: "soon") }
  end

  test "the name goes through the model's validation" do
    assert_refused("Name can't be blank", Event) { create_event(:admin, name: " ") }
  end

  test "times must be ISO 8601 date-times" do
    [ "soon", "2026-03-10", "03/10/2026 18:00", "2026-02-31T18:00:00", "2026-13-01T18:00:00", "2026-03-10T25:00:00", "" ].each do |bad|
      assert_refused(/starts_at must be an ISO 8601/, Event) { create_event(:admin, starts_at: bad) }
      assert_refused(/ends_at must be an ISO 8601/, Event) { create_event(:admin, ends_at: bad) }
    end
  end

  test "an out-of-range offset is refused, not read as local time" do
    %w[+24:00 -24:00 +30:00 -99:00 +12:60 +05:99 +0560 -0560 +0599].each do |offset|
      assert_refused(/starts_at must be an ISO 8601/, Event) { create_event(:admin, starts_at: "#{STARTS}#{offset}", ends_at: "2030-01-01T00:00:00") }
    end
  end

  test "an offset at the edge of the range keeps its instant" do
    assert_equal Time.utc(2026, 3, 9, 18, 1), create_event(:admin, starts_at: "#{STARTS}+23:59").changed.start_time
    assert_equal Time.utc(2026, 3, 10, 4, 0), create_event(:admin, starts_at: "#{STARTS}+14:00").changed.start_time
  end

  test "ends_at must be after starts_at" do
    assert_refused("ends_at must be after starts_at", Event) { create_event(:admin, ends_at: "2026-03-10T17:00:00") }
    assert_refused("ends_at must be after starts_at", Event) { create_event(:admin, ends_at: STARTS) }
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "tm_nonsense", @access_badge.neat_id ].each do |bad|
      assert_refused("Not found", Event) do
        call_tool("create_event", user: user(:admin), team_id: bad, event_type_id: event_types(:one).neat_id, name: "x", starts_at: STARTS, ends_at: ENDS)
      end
      assert_refused("Not found", Event) do
        call_tool("create_event", user: user(:admin), team_id: @alpha.neat_id, event_type_id: bad, name: "x", starts_at: STARTS, ends_at: ENDS)
      end
    end
  end

  test "the team, type, name and times are required, and other attributes are ignored" do
    assert_refused(/team_id/, Event) { call_tool("create_event", user: user(:admin), event_type_id: event_types(:one).neat_id, name: "x", starts_at: STARTS, ends_at: ENDS) }
    assert_refused(/ends_at/, Event) { call_tool("create_event", user: user(:admin), team_id: @alpha.neat_id, event_type_id: event_types(:one).neat_id, name: "x", starts_at: STARTS) }

    event = create_event(:admin, locked: true, checkin_limit: 3).changed
    assert_nil event.locked
    assert_nil event.checkin_limit
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_refused("Not allowed", Event) { create_event(:admin, scopes: "mcp_read") }
    assert_refused("Writes disabled", Event) { create_event(:admin, writes_enabled: false) }
    with_feature(:events, false) { assert_refused("Feature off", Event) { create_event(:admin) } }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("events - create") { create_event(:admin) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @beta ],
      [ :alpha_manager, @alpha ],
      [ :alpha_manager, @child ],
      [ :alpha_manager, @beta ],
      [ :alpha_manager, @open_team ],
      [ :alpha_member, @alpha ],
      [ :beta_member, @alpha ],
      [ :guardian, @alpha ],
      [ :guardian, @open_team ]
    ].each do |viewer, team|
      page = page_changes_rows?(Event, as: user(viewer)) do
        post events_path, params: { event: { name: "Planning", start_time: STARTS, end_time: ENDS, event_type_id: event_types(:one).id, team_id: team.id } }
      end
      tool = changes_rows?(Event) { create_event(viewer, team) }

      assert_equal page, tool, "#{viewer} creating an event for #{team.name}"
    end
  end
end
