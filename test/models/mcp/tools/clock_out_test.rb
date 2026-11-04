require "test_helper"
require_relative "../../../support/mcp_world"

# The world's periods are all "added by admin". Open: alpha_manager in Alpha March (since
# 3/11 08:00) and beta_member in Beta March (since 3/11 09:00).
class Mcp::Tools::ClockOutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @ward_open = create_world_punch(person(:ward), @alpha_period, 30, nil)
    @beta_open = TimeClockPunch.where(person: person(:beta_member), end_time: nil).first
    travel_to MCP_TIME_NOW
  end

  def clock_out(viewer, **arguments)
    call_tool("clock_out", user: user(viewer), **arguments)
  end

  def changed_ids(result)
    result.value["changed"].map { |item| item["id"] }
  end

  def open_count
    TimeClockPunch.where(end_time: nil).count
  end

  test "an admin closes everything in every period, now, keeping the audit trail" do
    result = clock_out(:admin, all: true)

    assert_equal [ @open_punch, @ward_open, @beta_open ].map(&:neat_id).sort, changed_ids(result).sort
    assert_empty result.value["skipped"]
    assert_equal false, result.value["dry_run"]
    assert_equal MCP_TIME_NOW, @ward_open.reload.end_time
    assert_equal user(:admin).id.to_s, @ward_open.versions.where(event: "update").last.whodunnit
    assert_equal MCP_TIME_NOW.iso8601, result.value["changed"].find { |item| item["id"] == @ward_open.neat_id }["end_time"]
  end

  test "one call log row lists every changed record" do
    assert_difference("McpToolCall.count", 1) { clock_out(:admin, all: true) }

    row = McpToolCall.order(:created_at).last
    assert_equal [ @open_punch, @ward_open, @beta_open ].map(&:id).sort, row.changed_records.map { |record| record["id"] }.sort
    assert_nil row.changed_id
  end

  test "a manager closes punches on an added by admin period of their team" do
    result = clock_out(:alpha_manager, period_id: @alpha_period.neat_id)

    assert_equal [ @open_punch, @ward_open ].map(&:neat_id).sort, changed_ids(result).sort
    assert_nil @beta_open.reload.end_time
  end

  test "a manager's all covers their teams' periods only" do
    result = clock_out(:alpha_manager, all: true)

    assert_equal [ @open_punch, @ward_open ].map(&:neat_id).sort, changed_ids(result).sort
    assert_nil @beta_open.reload.end_time
  end

  test "a manager can't see another team's period, or close a punch someone they manage has there" do
    assert_equal "Not found", clock_out(:alpha_manager, period_id: @beta_period.neat_id).error
    assert_nil @beta_open.reload.end_time

    Membership.create!(person: person(:ward), team: @beta)
    other = create_world_punch(person(:ward), @beta_period, 34, nil)
    Membership.create!(person: person(:alpha_manager), team: @beta)

    assert_no_difference(-> { open_count }, "AuditLog.count") do
      result = clock_out(:alpha_manager, period_id: @beta_period.neat_id, dry_run: true)
      assert_equal [ { "id" => other.neat_id, "reason" => "Not allowed" } ], result.value["skipped"]
    end
    result = clock_out(:alpha_manager, person_id: person(:ward).neat_id)
    assert_equal [ @ward_open.neat_id ], changed_ids(result)
    assert_equal [ { "id" => other.neat_id, "reason" => "Not allowed" } ], result.value["skipped"]
    assert_nil other.reload.end_time
  end

  test "a manager's own punch on another team's period closes" do
    Membership.create!(person: person(:alpha_manager), team: @beta)
    own = create_world_punch(person(:alpha_manager), @beta_period, 34, nil)

    result = clock_out(:alpha_manager, person_id: person(:alpha_manager).neat_id)

    assert_includes changed_ids(result), own.neat_id
    assert_equal MCP_TIME_NOW, own.reload.end_time
  end

  test "someone who manages no team closes nothing, not even their own, in any form" do
    teammate = create_world_punch(person(:badge_holder), @beta_period, 33, nil)
    forms = [ { person_id: person(:beta_member).neat_id }, { person_id: person(:badge_holder).neat_id }, { period_id: @beta_period.neat_id }, { all: true } ]

    assert_no_difference(-> { open_count }, "AuditLog.count") do
      forms.each do |form|
        assert_equal "Not allowed", clock_out(:beta_member, **form).error, form
        assert_equal "Not allowed", clock_out(:beta_member, **form, dry_run: true).error, form
      end
    end
    assert_nil @beta_open.reload.end_time
    assert_nil teammate.reload.end_time
  end

  test "a guardian closes nothing, and isn't told whether a ward is clocked in" do
    assert_equal "Not allowed", clock_out(:guardian, person_id: person(:ward).neat_id).error
    assert_equal "Not allowed", clock_out(:guardian, period_id: @alpha_period.neat_id).error
    assert_equal "Not allowed", clock_out(:guardian, all: true).error
    assert_nil @ward_open.reload.end_time
  end

  test "a manager closes their own punch in no period" do
    own = TimeClockPunch.create!(person: person(:alpha_manager), start_time: Time.utc(2026, 3, 11, 8))

    assert_includes changed_ids(clock_out(:alpha_manager, person_id: person(:alpha_manager).neat_id)), own.neat_id
    assert_equal MCP_TIME_NOW, own.reload.end_time
  end

  test "a punch in no period: an admin closes it by person, a manager of the person can't, and all leaves it" do
    loose = TimeClockPunch.create!(person: person(:ward), start_time: Time.utc(2026, 3, 11, 8))

    assert_not_includes changed_ids(clock_out(:alpha_manager, all: true, dry_run: true)), loose.neat_id
    assert_not_includes changed_ids(clock_out(:admin, all: true, dry_run: true)), loose.neat_id
    assert_includes clock_out(:alpha_manager, person_id: person(:ward).neat_id).value["skipped"], { "id" => loose.neat_id, "reason" => "Not allowed" }
    assert_nil loose.reload.end_time

    assert_includes changed_ids(clock_out(:admin, person_id: person(:ward).neat_id)), loose.neat_id
    assert_equal MCP_TIME_NOW, loose.reload.end_time
  end

  test "a dry run changes nothing and lists the same punches a real run closes" do
    create_world_punch(person(:alpha_member), @alpha_period, 33, nil)
    preview = nil
    assert_no_difference(-> { open_count }, "AuditLog.count") { preview = clock_out(:alpha_manager, period_id: @alpha_period.neat_id, dry_run: true) }

    assert_equal true, preview.value["dry_run"]
    assert_empty McpToolCall.order(:created_at).last.changed_records
    assert_equal MCP_TIME_NOW.iso8601, preview.value["changed"].first["end_time"]
    real = clock_out(:alpha_manager, period_id: @alpha_period.neat_id)
    assert_equal 3, changed_ids(real).size
    assert_equal real.value["changed"].sort_by { |item| item["id"] }, preview.value["changed"].sort_by { |item| item["id"] }
  end

  test "a dry run shows the flags a punch will have once closed, and leaves it as it was" do
    preview = clock_out(:admin, person_id: person(:ward).neat_id, dry_run: true)

    assert_equal [ "too_long" ], preview.value["changed"].first["flags"]
    assert_nil @ward_open.reload.end_time
    assert_equal [ "still_clocked_in" ], call_tool("list_punches", user: user(:admin), from: "2026-03-11", to: "2026-03-11", person_id: person(:ward).neat_id).value["items"].first["flags"]
    assert_equal [ "too_long" ], clock_out(:admin, person_id: person(:ward).neat_id).value["changed"].first["flags"]
  end

  def punch_updates
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].match?(/\AUPDATE "time_clock_punches"/) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  test "a dry run asks for flags once, and writes nothing that lasts" do
    create_world_punch(person(:beta_member), @beta_period, 34, nil)

    assert_equal 2, punch_updates { clock_out(:admin, person_id: person(:beta_member).neat_id, dry_run: true) }
    assert_equal 2, TimeClockPunch.where(person: person(:beta_member), end_time: nil).count
  end

  test "an admin's all covers a team-less period too" do
    loose = create_world_punch(person(:guardian), @everyone_period, 33, nil)

    assert_includes changed_ids(clock_out(:admin, all: true)), loose.neat_id
    assert_equal MCP_TIME_NOW, loose.reload.end_time
  end

  test "a manager of a parent team closes a sub-team's period, as the kiosk's managed periods do" do
    parent = create_world_team("Parent")
    kid = create_world_team("Kid", parent: parent)
    @people[:parent_manager] = create_world_person("ParentManager", parent, manager: true)
    @people[:kid_member] = create_world_person("KidMember", kid)
    period = create_world_period("Kid March", kid)
    punch = create_world_punch(person(:kid_member), period, 33, nil)

    assert_equal [ punch.neat_id ], changed_ids(clock_out(:parent_manager, all: true))
    assert_equal MCP_TIME_NOW, punch.reload.end_time
  end

  test "a manager closes the open punch of someone who has since left their team" do
    Membership.find_by!(person: person(:ward), team: @alpha).destroy!

    assert_includes changed_ids(clock_out(:alpha_manager, all: true)), @ward_open.neat_id
    assert_equal MCP_TIME_NOW, @ward_open.reload.end_time
  end

  test "each punch is capped at the end of its period's last day" do
    travel_to Time.utc(2026, 4, 5, 12)
    result = clock_out(:admin, period_id: @alpha_period.neat_id)

    assert_equal 2, changed_ids(result).size
    assert_equal Time.utc(2026, 3, 31).end_of_day.to_i, @ward_open.reload.end_time.to_i
  end

  test "created_by stays out of it: a manager passes the model's check, and nothing is stored as kiosk" do
    clock_out(:alpha_manager, period_id: @alpha_period.neat_id)

    assert_not TimeClockPunch.column_names.include?("created_by")
    assert_not_nil @ward_open.reload.end_time
    assert_equal user(:alpha_manager).id.to_s, @ward_open.versions.where(event: "update").last.whodunnit
  end

  test "a punch that would end before it starts is skipped with the reason, in a dry run too" do
    future = create_world_punch(person(:ward), @alpha_period, 400, nil)

    [ true, false ].each do |dry_run|
      result = clock_out(:admin, person_id: person(:ward).neat_id, dry_run: dry_run)

      assert_equal [ @ward_open.neat_id ], changed_ids(result) if dry_run
      assert_equal [ { "id" => future.neat_id, "reason" => "End time cannot end before start time" } ], result.value["skipped"]
    end
    assert_nil future.reload.end_time
  end

  test "more than 200 is refused whole" do
    201.times { TimeClockPunch.insert({ person_id: person(:ward).id, time_clock_period_id: @alpha_period.id, start_time: Time.utc(2026, 3, 11, 8), created_at: Time.current, updated_at: Time.current }) }

    assert_no_difference(-> { open_count }) do
      assert_match(/at most 200/, clock_out(:admin, period_id: @alpha_period.neat_id).error)
      assert_match(/at most 200/, clock_out(:admin, period_id: @alpha_period.neat_id, dry_run: true).error)
    end
  end

  test "a hook on the model runs for each, and one that fails leaves the others" do
    Hook.create!(name: "Fails on one", event: "time_clock_punches - update", code: "raise 'boom' if model.person.first_name == 'Ward'")

    result = clock_out(:admin, period_id: @alpha_period.neat_id)

    assert_equal [ @open_punch.neat_id ], changed_ids(result)
    assert_equal [ { "id" => @ward_open.neat_id, "reason" => "Internal error" } ], result.value["skipped"]
    assert_match(/1 record failed unexpectedly/, McpToolCall.order(:created_at).last.error_message)
    assert_nil @ward_open.reload.end_time
  end

  test "exactly one of the three forms, and real types" do
    assert_no_difference(-> { open_count }) do
      message = "Give exactly one of person_id, period_id or all: true"
      assert_equal message, clock_out(:admin).error
      assert_equal message, clock_out(:admin, all: false).error
      assert_equal message, clock_out(:admin, all: true, period_id: @alpha_period.neat_id).error
      assert_equal message, clock_out(:admin, person_id: person(:ward).neat_id, period_id: @alpha_period.neat_id).error
      assert_match(/all/, clock_out(:admin, all: "no").error)
      assert_match(/dry_run/, clock_out(:admin, all: true, dry_run: "no").error)
      assert_equal "Not found", clock_out(:admin, person_id: "per_nonsense").error
    end
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_no_difference(-> { open_count }) do
      assert_equal "Not allowed", clock_out(:admin, all: true, scopes: "mcp_read").error
      assert_equal "Writes disabled", clock_out(:admin, all: true, writes_enabled: false).error
      with_feature(:time_tracking, false) { assert_equal "Feature off", clock_out(:admin, all: true).error }
    end
  end

  # Against the kiosk's All Periods and per-period buttons, through the real controller.
  def closed_by(viewer)
    closed = nil
    TimeClockPunch.transaction(requires_new: true) do
      open_before = TimeClockPunch.where(end_time: nil).pluck(:id)
      yield
      closed = open_before - TimeClockPunch.where(end_time: nil).pluck(:id)
      raise ActiveRecord::Rollback
    end
    closed.sort
  end

  def kiosk(viewer, **params)
    sign_in user(viewer)
    post time_kiosk_path, params: { time_kiosk: { person_id: person(viewer).id, person_ref: person(viewer).signed_id(purpose: :time_kiosk, expires_in: 5.minutes), **params } }
    sign_out user(viewer)
  end

  test "all closes what the kiosk's All Periods closes" do
    %i[alpha_manager beta_member].each do |viewer|
      page = closed_by(viewer) { kiosk(viewer, tool: "punch_out_all") }
      tool = closed_by(viewer) { clock_out(viewer, all: true) }

      assert_equal page, tool, viewer
    end
  end

  test "a period closes what the kiosk's per-period button closes, for a manager and a non-manager" do
    page = closed_by(:alpha_manager) { kiosk(:alpha_manager, tool: "punch_out_period", time_clock_period_id: @alpha_period.id) }
    tool = closed_by(:alpha_manager) { clock_out(:alpha_manager, period_id: @alpha_period.neat_id) }
    assert_equal 2, page.size
    assert_equal page, tool

    page = closed_by(:ward) { kiosk(:alpha_member, tool: "punch_out_period", time_clock_period_id: @alpha_period.id) }
    tool = closed_by(:ward) { clock_out(:alpha_member, period_id: @alpha_period.neat_id) }
    assert_empty page
    assert_equal page, tool
  end

  test "the same end time as the kiosk, capped or not" do
    travel_to Time.utc(2026, 4, 5, 12)
    kiosk(:ward, tool: "punch_out", time_clock_punch_id: @ward_open.id)
    page = @ward_open.reload.end_time

    other = create_world_punch(person(:alpha_member), @alpha_period, 33, nil)
    clock_out(:alpha_manager, person_id: person(:alpha_member).neat_id)
    assert_equal page, other.reload.end_time
  end
end
