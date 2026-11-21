require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RecordPunchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  STARTS = "2026-03-11T18:00:00".freeze
  ENDS = "2026-03-11T20:00:00".freeze

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @manager_period = period_with(:added_by_manager, @alpha, "Alpha Managers")
    @member_period = period_with(:added_by_team_member, @alpha, "Alpha Members")
    @open_period = period_with(:added_by_user, nil, "Anyone")
    travel_to MCP_TIME_NOW
  end

  def period_with(permission, team, name)
    TimeClockPeriod.create!(name: name, team: team, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: permission)
  end

  def record(viewer, holder, period: nil, **options)
    arguments = { person_id: person(holder).neat_id, starts_at: STARTS, **options }
    arguments[:period_id] = period.neat_id if period
    call_tool("record_punch", user: user(viewer), **arguments)
  end

  test "an admin records for anyone, and gets the punch back as list_punches shows it" do
    result = record(:admin, :beta_member, period: @beta_period, ends_at: ENDS, note: "From paper")

    punch = result.changed
    assert_equal person(:beta_member), punch.person
    assert_equal @beta_period, punch.time_clock_period
    assert_equal Time.utc(2026, 3, 11, 18), punch.start_time
    assert_equal "From paper", punch.note
    listed = call_tool("list_punches", user: user(:admin), from: "2026-03-11", to: "2026-03-11").value["items"].find { |item| item["id"] == punch.neat_id }
    assert_equal listed, result.value
    assert_equal 2.0, result.value["hours"]
    assert_equal user(:admin).id.to_s, punch.versions.last.whodunnit
  end

  test "leaving out ends_at leaves it open" do
    result = record(:admin, :ward, period: @alpha_period)

    assert_nil result.changed.end_time
    assert_nil result.value["end_time"]
  end

  test "a team manager records for their people in a manager period, and themselves" do
    assert_nil record(:alpha_manager, :ward, period: @manager_period).error
    assert_nil record(:alpha_manager, :alpha_manager, period: @manager_period).error
    assert_nil record(:alpha_manager, :ward).error
  end

  test "a manager can't record in an added by admin period, or for someone on another team" do
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:alpha_manager, :ward, period: @alpha_period) }
    assert_refused("Not found", TimeClockPunch, AuditLog) { record(:alpha_manager, :beta_member) }
  end

  test "someone who manages no team records nothing, for themselves or anyone" do
    [ nil, @open_period, @beta_period, @alpha_period, @member_period ].each do |period|
      assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:beta_member, :beta_member, period: period) }
      assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:beta_member, :beta_member, period: period, ends_at: ENDS) }
      assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:beta_member, :badge_holder, period: period) }
    end
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:alpha_member, :ward, period: @member_period) }
  end

  test "a manager records for a teammate they don't manage only in an added by team member period" do
    Membership.create!(person: person(:alpha_manager), team: @beta)
    member_period = period_with(:added_by_team_member, @beta, "Beta Members")
    user_period = period_with(:added_by_user, @beta, "Beta Users")

    assert_nil record(:alpha_manager, :beta_member, period: member_period).error
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:alpha_manager, :beta_member, period: user_period) }
    assert_nil record(:alpha_manager, :alpha_manager, period: user_period).error
  end

  test "a manager records for a teammate in an added by team member period, as the page does" do
    Membership.create!(person: person(:alpha_manager), team: @beta)
    member_period = period_with(:added_by_team_member, @beta, "Beta Members")
    arguments = { person_id: person(:beta_member).id, time_clock_period_id: member_period.id, start_time: STARTS }

    page = page_changes_rows?(TimeClockPunch, as: user(:alpha_manager)) { post time_clock_punches_path, params: { time_clock_punch: arguments } }
    tool = changes_rows?(TimeClockPunch) { record(:alpha_manager, :beta_member, period: member_period) }

    assert page
    assert_equal page, tool
  end

  test "a period's permission applies to an admin too: added by team member needs a member of its team" do
    period = period_with(:added_by_team_member, @beta, "Beta Members")

    assert_refused(/\ANot allowed: Time clock period does not meet/, TimeClockPunch, AuditLog) { record(:admin, :beta_member, period: period) }
    page = page_changes_rows?(TimeClockPunch, as: user(:admin)) do
      post time_clock_punches_path, params: { time_clock_punch: { person_id: person(:beta_member).id, time_clock_period_id: period.id, start_time: STARTS } }
    end
    assert_not page
  end

  test "a guardian records nothing" do
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:guardian, :ward) }
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { record(:guardian, :guardian) }
  end

  test "the model's rules come back: team membership, the period's dates and the order of the times" do
    assert_refused(/not a member of the team/, TimeClockPunch) { record(:admin, :beta_member, period: @alpha_period) }
    assert_refused(/cannot start before period start time/, TimeClockPunch) { record(:admin, :ward, period: @alpha_period, starts_at: "2026-02-01T10:00:00") }
    assert_refused(/cannot end after period end time/, TimeClockPunch) { record(:admin, :ward, period: @alpha_period, ends_at: "2026-04-02T10:00:00") }
    assert_refused(/cannot end before start time/, TimeClockPunch) { record(:admin, :ward, ends_at: "2026-03-11T17:00:00") }
  end

  test "malformed input is refused cleanly" do
    [ "soon", "2026-03-11", "2026-13-01T10:00:00", "99999-01-01T00:00:00Z", "" ].each do |bad|
      assert_refused("starts_at must be a time like 2026-03-31T18:00:00", TimeClockPunch) { record(:admin, :ward, starts_at: bad) }
      assert_refused("ends_at must be a time like 2026-03-31T18:00:00", TimeClockPunch) { record(:admin, :ward, ends_at: bad) }
    end
    assert_refused(/starts_at/, TimeClockPunch) { call_tool("record_punch", user: user(:admin), person_id: person(:ward).neat_id) }
    assert_refused(/.+/, TimeClockPunch) { record(:admin, :ward, end_time: ENDS) }
    assert_refused(/line breaks/, TimeClockPunch) { record(:admin, :ward, note: "one\ntwo") }
    assert_refused("Not found", TimeClockPunch) { call_tool("record_punch", user: user(:admin), person_id: "per_nonsense", starts_at: STARTS) }
  end

  test "an impossible time is refused, not rolled over to another one" do
    [ "2026-02-30T10:00", "2026-03-11T18:00:00+25:00", "2026-03-11T18:00:00+12:60", "2026-03-11T24:00:00", "2026-03-11T18:60:00", "2026-03-11T18:00:60", "2026-03-11T18:00:00 tomorrow" ].each do |bad|
      assert_refused("starts_at must be a time like 2026-03-31T18:00:00", TimeClockPunch) { record(:admin, :ward, starts_at: bad) }
    end
    [ "2026-03-11T18:00", "2026-03-11T18:00:00", "2026-03-11T18:00:00.5Z", "2026-03-11T18:00:00Z", "2026-03-11T18:00:00+14:00", "2026-03-11T18:00:00-0500" ].each do |good|
      assert_nil record(:admin, :ward, starts_at: good).error, good
    end
  end

  test "a tab in a note is taken, as the page's input can send one" do
    assert_equal "tab\there", record(:admin, :ward, note: "tab\there").changed.note
    post_note = page_changes_rows?(TimeClockPunch, as: user(:admin)) do
      post time_clock_punches_path, params: { time_clock_punch: { person_id: person(:ward).id, start_time: STARTS, note: "tab\there" } }
    end
    assert post_note
  end

  test "an offset is honored, and a bare time is in the site's zone" do
    assert_equal Time.utc(2026, 3, 11, 23), record(:admin, :ward, starts_at: "2026-03-11T18:00:00-05:00").changed.start_time
    with_settings(time_zone: "Eastern Time (US & Canada)") do
      assert_equal Time.utc(2026, 3, 11, 22), record(:admin, :ward).changed.start_time
    end
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_refused("Not allowed", TimeClockPunch) { record(:admin, :ward, scopes: "mcp_read") }
    assert_refused("Writes disabled", TimeClockPunch) { record(:admin, :ward, writes_enabled: false) }
    with_feature(:time_tracking, false) { assert_refused("Feature off", TimeClockPunch) { record(:admin, :ward) } }
  end

  test "a hook on the model runs, as on the page" do
    Thread.current[:mcp_hook_model] = nil
    Hook.create!(name: "MCP test hook", event: "time_clock_punches - create", code: "Thread.current[:mcp_hook_model] = model")

    assert_equal record(:admin, :ward).changed, Thread.current[:mcp_hook_model]
  ensure
    Thread.current[:mcp_hook_model] = nil
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, :beta_member, @beta_period ],
      [ :admin, :beta_member, @alpha_period ],
      [ :alpha_manager, :ward, @manager_period ],
      [ :alpha_manager, :ward, @alpha_period ],
      [ :alpha_manager, :alpha_manager, nil ],
      [ :admin, :guardian, @open_period ]
    ].each do |viewer, holder, period|
      page = page_changes_rows?(TimeClockPunch, as: user(viewer)) do
        post time_clock_punches_path, params: { time_clock_punch: { person_id: person(holder).id, time_clock_period_id: period&.id, start_time: STARTS } }
      end
      tool = changes_rows?(TimeClockPunch) { record(viewer, holder, period: period) }

      assert_equal page, tool, "#{viewer} recording for #{holder} in #{period&.name}"
    end
  end

  test "a build whose policy defines create? applies it too" do
    with_policy_query(TimeClockPunchPolicy, :create?, -> { false }) do
      assert_refused("Not allowed", TimeClockPunch) { record(:admin, :ward) }
    end
  end
end
