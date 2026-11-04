require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::MarkAllBroughtTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpSignupsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
    @own = create_signup(@cookies, :organizer, @bake_day)
    @plain = create_signup(@cookies, :alpha_plain, @bake_day)
    @elsewhere = create_signup(@cookies, :alpha_plain, @cleanup)
  end

  def mark_all(viewer, sheet = @sheet, event = @bake_day, **options)
    call_tool("mark_all_brought", user: user(viewer), sheet_id: sheet.neat_id, event_id: event.neat_id, **options)
  end

  def page_mark_all(viewer, sheet = @sheet, event = @bake_day)
    sign_in user(viewer)
    patch mark_all_brought_signup_sheet_roster_signups_path(sheet), params: { event_id: event.id }
    sign_out user(viewer)
  end

  def changed_ids(result)
    result.value["changed"].map { |item| item["id"] }
  end

  # The sign-ups the block marks fulfilled. The changes are rolled back.
  def marked_by
    marked = nil
    Signup.transaction(requires_new: true) do
      before = Signup.fulfilled.ids
      yield
      marked = Signup.fulfilled.ids - before
      raise ActiveRecord::Rollback
    end
    marked.sort
  end

  def assert_none_marked(error, viewer, *arguments, **options)
    before = Signup.order(:id).pluck(:id, :status)
    result = assert_refused(error, Signup, AuditLog) { mark_all(viewer, *arguments, **options) }
    assert_equal before, Signup.order(:id).pluck(:id, :status)
    result
  end

  test "it marks the event's active item sign-ups, leaves everything else, and lists the organizer's own" do
    result = mark_all(:organizer)

    assert_nil result.error
    assert_equal [ @ward_cookies, @plain ].map(&:neat_id).sort, changed_ids(result).sort
    assert_equal [ { "id" => @own.neat_id, "reason" => SignupSheet::SELF_APPROVAL_REASON } ], result.value["skipped"]
    assert_equal false, result.value["dry_run"]
    assert_equal [ "fulfilled" ], result.value["changed"].map { |item| item["status"] }.uniq

    assert @ward_cookies.reload.fulfilled?
    assert @plain.reload.fulfilled?
    assert @own.reload.active?
    assert @no_show.reload.no_show?
    assert @elsewhere.reload.active?
    assert @bake_day_cashier.reload.active?
  end

  test "each item is the roster's row" do
    result = mark_all(:organizer)
    item = result.value["changed"].find { |row| row["id"] == @ward_cookies.neat_id }

    sheet = call_tool("get_signup_sheet", user: user(:organizer), sheet_id: @sheet.neat_id).value
    row = sheet["events"].flat_map { |event| event["slots"] }.flat_map { |slot| slot["signups"] }.find { |signup| signup["id"] == @ward_cookies.neat_id }
    assert_equal row, item.slice(*row.keys)
    assert_equal "Cookies", item.dig("position", "name")
  end

  test "an admin and a team manager are organizers too, and a relative's sign-up is left" do
    Relationship.create!(parent: person(:alpha_manager), child: person(:alpha_plain), relationship_type: @parent_of, created_by: person(:admin))

    manager = mark_all(:alpha_manager)
    assert_equal [ @ward_cookies, @own ].map(&:neat_id).sort, changed_ids(manager).sort
    assert_equal [ @plain.neat_id ], manager.value["skipped"].map { |skip| skip["id"] }

    assert_equal [ @plain.neat_id ], changed_ids(mark_all(:admin))
  end

  test "a plain member and a guardian are refused, and someone outside the audience doesn't see it" do
    assert_none_marked("Not allowed", :alpha_plain)
    assert_none_marked("Not allowed", :guardian)
    assert_none_marked("Not found", :beta_member)
    assert_none_marked("Not found", :alpha_member, @beta_sheet, @beta_day)
    assert_equal "denied", McpToolCall.where(tool: "mark_all_brought").order(:created_at).first.outcome
  end

  test "an event not on the sheet is not found, and so are bad IDs" do
    assert_none_marked("Not found", :admin, @sheet, @beta_day)
    assert_refused("Not found", Signup) { call_tool("mark_all_brought", user: user(:admin), sheet_id: "sush_nonsense", event_id: @bake_day.neat_id) }
    assert_refused("Not found", Signup) { call_tool("mark_all_brought", user: user(:admin), sheet_id: @sheet.neat_id, event_id: @alpha.neat_id) }
    assert_refused(/event_id/, Signup) { call_tool("mark_all_brought", user: user(:admin), sheet_id: @sheet.neat_id) }
  end

  test "an archived sheet is refused" do
    assert_none_marked("This sheet is archived", :admin, @archived_sheet)
  end

  test "dry_run lists what a real run changes and changes nothing" do
    versions = AuditLog.count
    preview = nil
    assert_no_changes(-> { Signup.order(:id).pluck(:id, :status) }) { preview = mark_all(:organizer, dry_run: true) }

    assert_equal versions, AuditLog.count
    assert_equal true, preview.value["dry_run"]
    log = McpToolCall.order(:created_at).last
    assert_empty log.changed_records
    assert_equal true, log.arguments["dry_run"]

    real = mark_all(:organizer, dry_run: false)
    assert_equal changed_ids(real), changed_ids(preview)
    assert_equal real.value["skipped"], preview.value["skipped"]
  end

  test "dry_run must be a boolean: no is not false" do
    [ "no", "true", 0 ].each { |value| assert_none_marked(/dry_run/, :organizer, dry_run: value) }
  end

  test "one call log row holds every changed record" do
    result = nil
    assert_difference("McpToolCall.count", 1) { result = mark_all(:organizer) }
    log = McpToolCall.order(:created_at).last

    assert_equal [ "mark_all_brought", "ok" ], [ log.tool, log.outcome ]
    assert_equal [ @ward_cookies.id, @plain.id ].sort, log.changed_records.map { |record| record["id"] }.sort
    assert_equal [ "Signup" ], log.changed_records.map { |record| record["type"] }.uniq
    assert_equal user(:organizer).id.to_s, @plain.reload.versions.where(event: "update").last.whodunnit
  end

  test "a repeat finds nothing left to mark" do
    mark_all(:organizer)
    result = mark_all(:organizer)

    assert_empty result.value["changed"]
    assert_equal [ @own.neat_id ], result.value["skipped"].map { |skip| skip["id"] }
  end

  test "200 is the most a call changes: one more refuses the whole call, dry run or not" do
    198.times { create_signup(@cookies, :alpha_plain, @bake_day) }
    assert_equal 200, mark_all(:organizer, dry_run: true).value["changed"].size

    create_signup(@cookies, :alpha_plain, @bake_day)
    assert_none_marked(/at most 200\z/, :organizer)
    assert_none_marked(/at most 200\z/, :organizer, dry_run: true)
  end

  test "each sign-up's save runs its hooks" do
    Thread.current[:mcp_hook_models] = []
    Hook.create!(name: "Collect", event: "signups - fulfilled", code: "Thread.current[:mcp_hook_models] << model.id")

    mark_all(:organizer)

    assert_equal [ @ward_cookies.id, @plain.id ].sort, Thread.current[:mcp_hook_models].sort
  ensure
    Thread.current[:mcp_hook_models] = nil
  end

  test "one that fails is listed, and the others still go ahead" do
    Hook.create!(name: "Fail one", event: "signups - fulfilled", code: "raise 'boom' if model.id == #{@plain.id.to_json}")

    result = mark_all(:organizer)

    assert_nil result.error
    assert_equal [ @ward_cookies.neat_id ], changed_ids(result)
    assert_includes result.value["skipped"], { "id" => @plain.neat_id, "reason" => "Internal error" }
    assert @ward_cookies.reload.fulfilled?
    assert_match "1 record failed", McpToolCall.order(:created_at).last.error_message
  end

  test "a read token, the setting being off and the feature being off refuse it" do
    assert_none_marked("Not allowed", :admin, scopes: "mcp_read")
    assert_none_marked("Writes disabled", :admin, writes_enabled: false)
    with_feature(:signups, false) { assert_none_marked("Feature off", :admin) }
  end

  test "it marks what the page marks and refuses as the page does" do
    [ :organizer, :alpha_manager, :admin, :alpha_plain, :guardian, :beta_member ].each do |viewer|
      page = marked_by { page_mark_all(viewer) }
      tool = marked_by { mark_all(viewer) }

      assert_equal page, tool, "as #{viewer}"
      assert_equal viewer.in?(%i[ organizer alpha_manager admin ]), tool.any?, "as #{viewer}"
    end

    assert_empty marked_by { page_mark_all(:admin, @archived_sheet) }
    assert_empty marked_by { mark_all(:admin, @archived_sheet) }
  end
end
