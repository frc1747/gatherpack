require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::UpdatePunchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @manager_period = TimeClockPeriod.create!(name: "Alpha Managers", team: @alpha, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: :added_by_manager)
    @other_period = TimeClockPeriod.create!(name: "Alpha Other", team: @alpha, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: :added_by_manager)
    @punch = create_world_punch(person(:ward), @manager_period, 10, 12)
    @admin_punch = create_world_punch(person(:ward), @alpha_period, 14, 16)
    @own = TimeClockPunch.create!(person: person(:beta_member), start_time: Time.utc(2026, 3, 10, 9), end_time: Time.utc(2026, 3, 10, 10), note: "Mine")
    travel_to MCP_TIME_NOW
  end

  def update(viewer, punch, **changes)
    call_tool("update_punch", user: user(viewer), punch_id: punch.neat_id, **changes)
  end

  def assert_unchanged(punch)
    before = punch.reload.attributes
    assert_no_difference("AuditLog.count") { yield }
    assert_equal before, punch.reload.attributes
  end

  test "an admin changes any field, and gets the punch back as list_punches shows it" do
    result = update(:admin, @admin_punch, starts_at: "2026-03-10T13:00:00", ends_at: "2026-03-10T17:00:00", note: "Fixed")

    @admin_punch.reload
    assert_equal Time.utc(2026, 3, 10, 13), @admin_punch.start_time
    assert_equal Time.utc(2026, 3, 10, 17), @admin_punch.end_time
    assert_equal "Fixed", @admin_punch.note
    assert_equal @admin_punch, result.changed
    assert_equal 4.0, result.value["hours"]
    assert_equal "Fixed", result.value["note"]
    assert_equal user(:admin).id.to_s, @admin_punch.versions.where(event: "update").last.whodunnit
  end

  test "only what's sent changes; null reopens, clears the note, and takes it out of its period" do
    update(:admin, @punch, note: "Kept")
    update(:admin, @punch, ends_at: nil)
    assert_nil @punch.reload.end_time
    assert_equal "Kept", @punch.note
    assert_equal @manager_period, @punch.time_clock_period

    update(:admin, @punch, note: nil, period_id: nil)
    @punch.reload
    assert_nil @punch.note
    assert_nil @punch.time_clock_period
  end

  test "a team manager edits a manager period's punch, but not an added by admin one" do
    assert_nil update(:alpha_manager, @punch, note: "ok").error

    assert_unchanged(@admin_punch) { assert_equal "Not allowed", update(:alpha_manager, @admin_punch, note: "no").error }
  end

  test "a manager can't reach a punch outside their scope" do
    beta_punch = create_world_punch(person(:beta_member), @beta_period, 20, 21)

    assert_unchanged(beta_punch) { assert_equal "Not found", update(:alpha_manager, beta_punch, note: "no").error }
  end

  test "someone who manages no team changes nothing, and isn't told what exists" do
    [ :beta_member, :guardian ].each do |viewer|
      assert_unchanged(@punch) { assert_equal "Not allowed", update(viewer, @punch, note: "no").error }
    end
  end

  test "a member changes nothing on their own punch, open or closed, in any period" do
    Membership.find_or_create_by!(person: person(:beta_member), team: @beta)
    Membership.find_or_create_by!(person: person(:badge_holder), team: @beta)
    periods = [ nil ] + %i[added_by_user added_by_team_member added_by_manager added_by_admin].map do |permission|
      TimeClockPeriod.create!(name: permission.to_s, team: @beta, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: permission)
    end

    periods.each do |period|
      [ nil, Time.utc(2026, 3, 11, 10) ].each do |end_time|
        punch = TimeClockPunch.create!(person: person(:beta_member), time_clock_period: period, start_time: Time.utc(2026, 3, 11, 9), end_time: end_time, created_by: "kiosk")
        [ { ends_at: "2026-03-11T11:00:00" }, { ends_at: nil }, { starts_at: "2026-03-12T09:00:00" }, { note: "no" }, { person_id: person(:badge_holder).neat_id }, { period_id: nil } ].each do |change|
          assert_unchanged(punch) { assert_equal "Not allowed", update(:beta_member, punch, **change).error, change }
        end
      end
    end
  end

  test "managers and admins close open punches they can edit" do
    open = create_world_punch(person(:ward), @manager_period, 30, nil)
    assert_nil update(:alpha_manager, open, ends_at: "2026-03-11T12:00:00").error
    assert_not_nil open.reload.end_time

    own = TimeClockPunch.create!(person: person(:alpha_manager), start_time: Time.utc(2026, 3, 11, 9))
    assert_nil update(:alpha_manager, own, ends_at: "2026-03-11T12:00:00").error

    other = TimeClockPunch.create!(person: person(:beta_member), start_time: Time.utc(2026, 3, 11, 9))
    assert_nil update(:admin, other, ends_at: "2026-03-11T12:00:00").error
  end

  test "moving a punch to another person needs that person: see, then may record for" do
    moved = update(:alpha_manager, @punch, person_id: person(:alpha_member).neat_id)
    assert_nil moved.error
    assert_equal person(:alpha_member), @punch.reload.person

    assert_unchanged(@punch) { assert_equal "Not found", update(:alpha_manager, @punch, person_id: person(:beta_member).neat_id).error }
    Membership.create!(person: person(:alpha_manager), team: @beta)
    own = TimeClockPunch.create!(person: person(:alpha_manager), start_time: Time.utc(2026, 3, 10, 9))
    assert_unchanged(own) { assert_equal "Not allowed", update(:alpha_manager, own, person_id: person(:beta_member).neat_id).error }
  end

  test "moving to another person needs create? where the policy defines it; other changes don't" do
    rule = -> { user.admin }
    with_policy_query(TimeClockPunchPolicy, :create?, rule) do
      assert_unchanged(@punch) { assert_equal "Not allowed", update(:alpha_manager, @punch, person_id: person(:alpha_member).neat_id).error }
      assert_nil update(:alpha_manager, @punch, note: "No move").error
      assert_nil update(:admin, @punch, person_id: person(:alpha_member).neat_id).error
    end
  end

  test "moving to another period needs create? where the policy defines it" do
    with_policy_query(TimeClockPunchPolicy, :create?, -> { user.admin }) do
      assert_unchanged(@punch) { assert_equal "Not allowed", update(:alpha_manager, @punch, period_id: @other_period.neat_id).error }
      assert_nil update(:admin, @punch, period_id: @other_period.neat_id).error
    end
  end

  test "sending back the punch's own person or period isn't a lookup, or a move" do
    with_policy_query(PersonPolicy::Scope, :resolve, -> { scope.none }) do
      assert_nil update(:alpha_manager, @punch, person_id: person(:ward).neat_id, note: "Same person").error
    end
    with_policy_query(TimeClockPeriodPolicy::Scope, :resolve, -> { scope.none }) do
      assert_nil update(:alpha_manager, @punch, period_id: @manager_period.neat_id, note: "Same period").error
      assert_equal "Not found", update(:alpha_manager, @punch, period_id: @alpha_period.neat_id).error
    end
    assert_equal person(:ward), @punch.reload.person
    assert_equal @manager_period, @punch.time_clock_period
    assert_equal "Same period", @punch.note
  end

  test "a period's permission and rules come back, and nothing changes" do
    assert_unchanged(@punch) { assert_match(/\ANot allowed: Time clock period does not meet/, update(:alpha_manager, @punch, period_id: @alpha_period.neat_id).error) }
    assert_unchanged(@punch) { assert_equal "Not found", update(:alpha_manager, @punch, period_id: @beta_period.neat_id).error }
    assert_unchanged(@punch) { assert_match(/not a member of the team/, update(:admin, @punch, period_id: @beta_period.neat_id).error) }
    assert_unchanged(@punch) { assert_match(/cannot end before start time/, update(:admin, @punch, ends_at: "2026-03-09T00:00:00").error) }
  end

  test "bad input is refused cleanly" do
    assert_unchanged(@punch) do
      assert_match(/Give at least one/, update(:admin, @punch).error)
      assert_match(/starts_at/, update(:admin, @punch, starts_at: nil).error)
      assert_match(/must be a time/, update(:admin, @punch, ends_at: "soon").error)
      assert_match(/end_time/, update(:admin, @punch, end_time: "2026-03-10T12:00:00").error)
      assert_equal "Not found", call_tool("update_punch", user: user(:admin), punch_id: "tcp_nonsense", note: "x").error
    end
  end

  test "a read token and the setting being off refuse it" do
    assert_unchanged(@punch) do
      assert_equal "Not allowed", update(:admin, @punch, note: "x", scopes: "mcp_read").error
      assert_equal "Writes disabled", update(:admin, @punch, note: "x", writes_enabled: false).error
    end
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @admin_punch, true ],
      [ :alpha_manager, @punch, true ],
      [ :alpha_manager, @admin_punch, false ],
      [ :admin, @own, true ]
    ].each do |viewer, punch, expected|
      page = note_changes?(punch) do
        sign_in user(viewer)
        patch time_clock_punch_path(punch), params: { time_clock_punch: { note: "Same note" } }
        sign_out user(viewer)
      end
      tool = note_changes?(punch) { update(viewer, punch, note: "Same note") }

      assert_equal expected, page, "page: #{viewer}"
      assert_equal page, tool, "#{viewer} changing #{punch.neat_id}"
    end
  end

  def note_changes?(punch)
    changed = false
    TimeClockPunch.transaction(requires_new: true) do
      yield
      changed = punch.reload.note == "Same note"
      raise ActiveRecord::Rollback
    end
    punch.reload
    changed
  end
end
