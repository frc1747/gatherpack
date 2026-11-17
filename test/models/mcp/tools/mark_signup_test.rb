require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::MarkSignupTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpSignupsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
  end

  def mark(viewer, signup, status = "fulfilled", **options)
    call_tool("mark_signup", user: user(viewer), signup_id: signup.neat_id, status: status, **options)
  end

  def page_mark(viewer, signup, status)
    sign_in user(viewer)
    patch mark_signup_sheet_roster_signup_path(signup.signup_sheet, signup), params: { status: status }
    sign_out user(viewer)
  end

  # As call_tool, for a call that may make no change, which call_tool doesn't allow.
  def run_mark(viewer, signup, status)
    with_settings(mcp_write_enabled: "true") do
      Mcp.tool("mark_signup").run(mcp_context(user(viewer), scopes: "mcp_write"), { signup_id: signup.neat_id, status: status })
    end
  end

  def assert_not_marked(error, viewer, signup, status = "fulfilled", **options)
    before = signup.reload.attributes
    result = assert_refused(error, Signup, AuditLog) { mark(viewer, signup, status, **options) }
    assert_equal before, signup.reload.attributes
    result
  end

  # The status the block leaves the sign-up in. The change is rolled back.
  def status_after(signup)
    status = nil
    Signup.transaction(requires_new: true) do
      yield
      status = signup.reload.status
      raise ActiveRecord::Rollback
    end
    signup.reload
    status
  end

  test "an organizer marks a sign-up and gets it back as the roster shows it" do
    result = mark(:organizer, @bake_day_cashier)

    assert_nil result.error
    assert @bake_day_cashier.reload.fulfilled?
    assert_equal @bake_day_cashier, result.changed
    assert_equal [ @bake_day_cashier.neat_id, "fulfilled", "Bring change", true ], result.value.values_at("id", "status", "note", "changed")

    sheet = call_tool("get_signup_sheet", user: user(:organizer), sheet_id: @sheet.neat_id).value
    row = sheet["events"].flat_map { |event| event["slots"] }.flat_map { |slot| slot["signups"] }.find { |signup| signup["id"] == @bake_day_cashier.neat_id }
    assert_equal row, result.value.slice(*row.keys)
  end

  test "an admin and a team manager are organizers too" do
    assert_nil mark(:admin, @bake_day_cashier).error
    assert_nil mark(:alpha_manager, @ward_cashier).error
    assert @ward_cashier.reload.fulfilled?
  end

  test "a plain member and a guardian are refused, and someone outside the audience doesn't see it" do
    assert_not_marked("Not allowed", :alpha_plain, @bake_day_cashier)
    assert_not_marked("Not allowed", :alpha_member, @bake_day_cashier)
    assert_not_marked("Not allowed", :guardian, @ward_cashier)
    assert_not_marked("Not found", :beta_member, @bake_day_cashier)
    assert_not_marked("Not found", :alpha_member, @beta_signup)
  end

  test "no one marks their own sign-up or a relative's" do
    own = create_signup(@cashier, :organizer, @cleanup)
    Relationship.create!(parent: person(:organizer), child: person(:late), relationship_type: @parent_of, created_by: person(:admin))
    relatives = create_signup(@cashier, :late, @cleanup)

    assert_not_marked("Not allowed", :organizer, own)
    assert_not_marked("Not allowed", :organizer, relatives)
    assert_nil mark(:admin, relatives).error
  end

  test "an item position's fulfilled is what the roster calls Brought" do
    assert_equal "fulfilled", mark(:organizer, @ward_cookies).value["status"]
    assert_equal "no_show", mark(:organizer, @past_signup, "no_show").value["status"]
  end

  test "only the roster's statuses are taken" do
    [ "brought", "cancelled", "", "FULFILLED", 2, true ].each do |status|
      assert_not_marked(/status/, :organizer, @bake_day_cashier, status)
    end
    assert_refused(/status/, Signup, AuditLog) { call_tool("mark_signup", user: user(:organizer), signup_id: @bake_day_cashier.neat_id) }
  end

  test "a no-show only once the event has started" do
    assert_not_marked("Mark no-shows once the event has started", :organizer, @bake_day_cashier, "no_show")

    assert_nil mark(:organizer, @past_signup, "no_show").error
    assert @past_signup.reload.no_show?
  end

  test "a cancelled sign-up can't be marked" do
    assert_not_marked("This sign-up was cancelled", :organizer, @cancelled)
    assert_not_marked("This sign-up was cancelled", :organizer, @cancelled, "active")
  end

  test "back to active undoes either mark" do
    @past_signup.update!(status: :no_show)
    assert_equal "active", mark(:organizer, @past_signup, "active").value["status"]

    @bake_day_cashier.update!(status: :fulfilled)
    assert_nil mark(:organizer, @bake_day_cashier, "active").error
    assert @bake_day_cashier.reload.active?
  end

  test "a closed sheet stops no organizer; an archived one stops everyone" do
    closed = create_signup(@closed_sheet.signup_positions.first, :alpha_member, @bake_day)
    archived = create_signup(@archived_sheet.signup_positions.first, :alpha_member, @bake_day)

    assert_nil mark(:admin, closed).error
    assert_not_marked("Not allowed", :admin, archived)
  end

  test "marking it with the status it has does what the page does, and says so" do
    @bake_day_cashier.update!(status: :fulfilled)
    versions = @bake_day_cashier.versions.count

    page_mark(:organizer, @bake_day_cashier, "fulfilled")
    assert @bake_day_cashier.reload.fulfilled?
    assert_equal versions, @bake_day_cashier.versions.count

    Thread.current[:mcp_hook_runs] = Hash.new(0)
    Hook.create!(name: "Status", event: "signups - fulfilled", code: "Thread.current[:mcp_hook_runs][:status] += 1")
    Hook.create!(name: "Update", event: "signups - update", code: "Thread.current[:mcp_hook_runs][:update] += 1")

    page_mark(:organizer, @bake_day_cashier, "fulfilled")
    assert_equal({ update: 1 }, Thread.current[:mcp_hook_runs])

    result = run_mark(:organizer, @bake_day_cashier, "fulfilled")

    assert_nil result.error
    assert_equal false, result.value["changed"]
    assert_equal "fulfilled", result.value["status"]
    assert_equal versions, @bake_day_cashier.reload.versions.count
    assert_equal({ update: 2 }, Thread.current[:mcp_hook_runs])

    assert_nil result.changed
    assert_empty result.changed_records
    log = McpToolCall.order(:created_at).last
    assert_equal [ "mark_signup", "ok", nil, nil, [] ], [ log.tool, log.outcome, log.changed_type, log.changed_id, log.changed_records ]
  ensure
    Thread.current[:mcp_hook_runs] = nil
  end

  test "undoing clears the check-in that fulfilled it, as the page's does" do
    checkin = Checkin.create!(person: person(:alpha_member), event: @bake_day, created_by: person(:admin))
    @bake_day_cashier.update_columns(status: Signup.statuses[:fulfilled], fulfilled_by_checkin_id: checkin.id)

    assert_nil mark(:organizer, @bake_day_cashier, "active").error
    assert_nil @bake_day_cashier.reload.fulfilled_by_checkin_id
  end

  test "a read token, the setting being off and the feature being off refuse it" do
    assert_not_marked("Not allowed", :admin, @bake_day_cashier, scopes: "mcp_read")
    assert_not_marked("Writes disabled", :admin, @bake_day_cashier, writes_enabled: false)
    with_feature(:signups, false) { assert_not_marked("Feature off", :admin, @bake_day_cashier) }
  end

  test "the call log and the audit log name the sign-up and the token's user" do
    mark(:organizer, @bake_day_cashier)
    log = McpToolCall.order(:created_at).last

    assert_equal [ "mark_signup", "ok", "Signup", @bake_day_cashier.id ], [ log.tool, log.outcome, log.changed_type, log.changed_id ]
    assert_equal user(:organizer).id.to_s, @bake_day_cashier.versions.where(event: "update").last.whodunnit
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("signups - fulfilled") { mark(:organizer, @bake_day_cashier) }
  end

  test "it allows and refuses as the page does" do
    own = create_signup(@cashier, :organizer, @cleanup)
    archived = create_signup(@archived_sheet.signup_positions.first, :alpha_member, @bake_day)

    [
      [ :organizer, @bake_day_cashier, "fulfilled", "fulfilled" ],
      [ :alpha_manager, @ward_cashier, "fulfilled", "fulfilled" ],
      [ :admin, @past_signup, "no_show", "no_show" ],
      [ :admin, @no_show, "active", "active" ],
      [ :organizer, @bake_day_cashier, "no_show", "active" ],
      [ :organizer, own, "fulfilled", "active" ],
      [ :organizer, @cancelled, "fulfilled", "cancelled" ],
      [ :alpha_plain, @bake_day_cashier, "fulfilled", "active" ],
      [ :guardian, @ward_cashier, "fulfilled", "active" ],
      [ :beta_member, @bake_day_cashier, "fulfilled", "active" ],
      [ :admin, archived, "fulfilled", "active" ]
    ].each do |viewer, signup, status, expected|
      label = "#{viewer} marking #{signup.identifier_name} #{status}"

      assert_equal expected, status_after(signup) { page_mark(viewer, signup, status) }, "page: #{label}"
      assert_equal expected, status_after(signup) { mark(viewer, signup, status) }, "tool: #{label}"
    end
  end
end
