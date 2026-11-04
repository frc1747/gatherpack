require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::MoveSignupTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpSignupsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
    @open_slot = slot_of(@cashier, @cleanup)
    @full_slot = slot_of(@cashier, @bake_day)
    clear_enqueued_jobs
  end

  def slot_of(position, event)
    position.signup_slots.find_by!(event: event)
  end

  def move(viewer, signup, slot = @open_slot, **options)
    call_tool("move_signup", user: user(viewer), signup_id: signup.neat_id, slot_id: slot.neat_id, **options)
  end

  def page_move(viewer, signup, slot, override_rules: false)
    sign_in user(viewer)
    params = { signup: { signup_slot_id: slot.id } }
    params[:signup][:override_rules] = "1" if override_rules
    patch move_signup_sheet_roster_signup_path(signup.signup_sheet, signup), params: params
    sign_out user(viewer)
  end

  # The call is refused with this error and leaves the sign-up and audit log as they were.
  def assert_not_moved(error, viewer, signup, slot = @open_slot, **options)
    before = signup.reload.attributes
    result = assert_refused(error, Signup, AuditLog) { move(viewer, signup, slot, **options) }
    assert_equal before, signup.reload.attributes
    result
  end

  def emails_from
    clear_enqueued_jobs
    yield
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args][1..3] }.sort
  end

  # Whether the block moves the sign-up to the slot. The change is rolled back.
  def moves?(signup, slot)
    moved = false
    Signup.transaction(requires_new: true) do
      yield
      moved = signup.reload.signup_slot_id == slot.id
      raise ActiveRecord::Rollback
    end
    signup.reload
    moved
  end

  def rule_on(position)
    license = create_world_badge("License")
    position.signup_position_rules.create!(kind: :badge, badge_ids: [ license.id ])
    license
  end

  def relate_to_organizer(name)
    Relationship.create!(parent: person(:organizer), child: person(name), relationship_type: @parent_of, created_by: person(:admin))
  end

  test "an organizer moves a sign-up and gets it back as the roster shows it" do
    result = nil
    assert_no_difference("Signup.count") { result = move(:organizer, @bake_day_cashier) }

    assert_nil result.error
    assert_equal @open_slot, @bake_day_cashier.reload.signup_slot
    assert_equal @bake_day_cashier, result.changed
    assert_equal true, result.value["changed"]
    assert_equal [ @bake_day_cashier.neat_id, "active", "Bring change" ], result.value.values_at("id", "status", "note")
    assert_equal [ "Bake Sale", "Clean-up", "Cashier" ], [ result.value.dig("sheet", "title"), result.value.dig("event", "name"), result.value.dig("position", "name") ]

    sheet = call_tool("get_signup_sheet", user: user(:organizer), sheet_id: @sheet.neat_id).value
    row = sheet["events"].flat_map { |event| event["slots"] }.flat_map { |slot| slot["signups"] }.find { |signup| signup["id"] == @bake_day_cashier.neat_id }
    assert_equal row, result.value.slice(*row.keys)
  end

  test "an admin and a team manager are organizers too" do
    assert_nil move(:admin, @bake_day_cashier).error
    assert_nil move(:alpha_manager, @ward_cashier).error
    assert_equal @open_slot, @ward_cashier.reload.signup_slot
  end

  test "a plain member and a guardian are refused, and someone outside the audience doesn't see it" do
    assert_not_moved("Not allowed", :alpha_plain, @bake_day_cashier)
    assert_not_moved("Not allowed", :alpha_member, @bake_day_cashier)
    assert_not_moved("Not allowed", :guardian, @ward_cashier)
    assert_not_moved("Not found", :beta_member, @bake_day_cashier)
    assert_not_moved("Not found", :alpha_member, @beta_signup, slot_of(@beta_sheet.signup_positions.first, @beta_day))
    assert_equal "denied", McpToolCall.where(tool: "move_signup").order(:created_at).first.outcome
  end

  test "no one moves their own sign-up or a relative's" do
    own = create_signup(@cashier, :organizer, @bake_day)
    relate_to_organizer(:late)
    relatives = create_signup(@cashier, :late, @past_event)
    on_behalf = create_signup(@cashier, :alpha_plain, @past_event, on_behalf_of: person(:late))

    assert_not_moved("Not allowed", :organizer, own)
    assert_not_moved("Not allowed", :organizer, relatives)
    assert_not_moved("Not allowed", :organizer, on_behalf)
    assert_not_moved("Not allowed", :organizer, relatives, override_rules: true)
    assert_nil move(:admin, relatives).error
  end

  test "the slot must be on the sign-up's sheet" do
    assert_not_moved("Not found", :admin, @bake_day_cashier, slot_of(@beta_sheet.signup_positions.first, @beta_day))
    assert_refused("Not found", Signup) { call_tool("move_signup", user: user(:admin), signup_id: @bake_day_cashier.neat_id, slot_id: "susl_nonsense") }
    assert_refused("Not found", Signup) { call_tool("move_signup", user: user(:admin), signup_id: @bake_day_cashier.neat_id, slot_id: @alpha.neat_id) }
    assert_refused("Not found", Signup) { call_tool("move_signup", user: user(:admin), signup_id: "sup_nonsense", slot_id: @open_slot.neat_id) }
    assert_refused(/slot_id/, Signup) { call_tool("move_signup", user: user(:admin), signup_id: @bake_day_cashier.neat_id) }
  end

  test "a full slot, a slot turned off and a cancelled sign-up are refused with the page's reason" do
    assert_not_moved("This slot is full", :organizer, @past_signup, @full_slot)

    @open_slot.update!(disabled: true)
    assert_not_moved("This slot is turned off", :organizer, @bake_day_cashier)
    @open_slot.update!(disabled: false)

    gone = create_signup(@cashier, :late, @bake_day, status: :cancelled)
    assert_not_moved("This sign-up was cancelled", :organizer, gone)
  end

  test "a position of another kind needs what that kind needs" do
    assert_not_moved("Quantity is needed", :organizer, @bake_day_cashier, slot_of(@cookies, @cleanup))
    assert_not_moved("Quantity is only for item positions", :organizer, @ward_cookies)
  end

  test "a failing rule refuses the move until override_rules is set" do
    greeter = @sheet.signup_positions.create!(name: "Greeter")
    rule_on(greeter)
    slot = slot_of(greeter, @cleanup)

    result = assert_not_moved(/License|badge/i, :organizer, @bake_day_cashier, slot)
    assert_not_equal "Internal error", result.error
    assert_not_moved(/License|badge/i, :organizer, @bake_day_cashier, slot, override_rules: false)

    assert_nil move(:organizer, @bake_day_cashier, slot, override_rules: true).error
    assert_equal slot, @bake_day_cashier.reload.signup_slot
  end

  test "override_rules must be a boolean: no is not yes" do
    greeter = @sheet.signup_positions.create!(name: "Greeter")
    rule_on(greeter)

    [ "no", "yes", "1", 1 ].each do |value|
      assert_not_moved(/override_rules/, :organizer, @bake_day_cashier, slot_of(greeter, @cleanup), override_rules: value)
    end
  end

  test "an organizer moves on a draft or closed sheet, and not an archived one" do
    [ @draft_sheet, @closed_sheet ].each do |sheet|
      position = sheet.signup_positions.first
      position.update!(capacity: 5)
      signup = create_signup(position, :alpha_member, @bake_day)
      other = sheet.signup_positions.create!(name: "Other")
      assert_nil move(:admin, signup, slot_of(other, @bake_day)).error
    end

    position = @archived_sheet.signup_positions.first
    signup = create_signup(position, :alpha_member, @bake_day)
    assert_not_moved("Not allowed", :admin, signup, slot_of(@archived_sheet.signup_positions.create!(name: "Other"), @bake_day))
  end

  test "a read token, the setting being off and the feature being off refuse it" do
    assert_not_moved("Not allowed", :admin, @bake_day_cashier, scopes: "mcp_read")
    assert_not_moved("Writes disabled", :admin, @bake_day_cashier, writes_enabled: false)
    with_feature(:signups, false) { assert_not_moved("Feature off", :admin, @bake_day_cashier) }
  end

  test "the call log and the audit log name the sign-up and the token's user" do
    move(:organizer, @bake_day_cashier)
    log = McpToolCall.order(:created_at).last

    assert_equal [ "move_signup", "ok", "Signup", @bake_day_cashier.id ], [ log.tool, log.outcome, log.changed_type, log.changed_id ]
    assert_equal user(:organizer).id.to_s, @bake_day_cashier.versions.where(event: "update").last.whodunnit
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("signups - update") { move(:organizer, @bake_day_cashier) }
  end

  test "it sends the same notices as the roster's Move, and reschedules the reminder" do
    page = emails_from { page_move(:organizer, @ward_cashier, @open_slot) }
    assert_equal @open_slot, @ward_cashier.reload.signup_slot
    page_reminders = enqueued_jobs.count { |job| job[:job] == SignupReminderJob }
    @ward_cashier.update_columns(signup_slot_id: @full_slot.id)

    emails = emails_from { assert_nil move(:organizer, @ward_cashier).error }

    assert_equal [ user(:guardian).email, user(:ward).email ].sort, emails.map(&:first)
    assert_match "Sign-up moved: Cashier, Clean-up", emails.first[1]
    assert_match "Organizer World moved Ward World&#39;s sign-up", emails.first[2]
    assert_equal page, emails
    assert_equal page_reminders, enqueued_jobs.count { |job| job[:job] == SignupReminderJob }
  end

  test "moving it to the slot it's in does what the page does: nothing new, no notices, and it says so" do
    versions = @bake_day_cashier.versions.count
    assert_empty(emails_from { page_move(:organizer, @bake_day_cashier, @full_slot) })
    assert_equal @full_slot, @bake_day_cashier.reload.signup_slot

    result = nil
    emails = emails_from { result = move(:organizer, @bake_day_cashier, @full_slot) }
    assert_nil result.error
    assert_equal false, result.value["changed"]
    assert_empty emails
    assert_equal versions, @bake_day_cashier.reload.versions.count
    assert_equal @full_slot, @bake_day_cashier.signup_slot
  end

  test "repeating a move sends its notices once, and tells the client the second did nothing" do
    first = nil
    assert_equal 1, emails_from { first = move(:organizer, @bake_day_cashier) }.size
    assert_equal true, first.value["changed"]

    second = nil
    assert_empty(emails_from { second = move(:organizer, @bake_day_cashier) })
    assert_equal false, second.value["changed"]
  end

  test "a refusal sends no email" do
    assert_empty(emails_from { move(:alpha_plain, @bake_day_cashier) })
    assert_empty(emails_from { move(:organizer, @past_signup, @full_slot) })
  end

  test "it allows and refuses as the page does" do
    greeter = @sheet.signup_positions.create!(name: "Greeter")
    rule_on(greeter)
    ruled = slot_of(greeter, @cleanup)
    own = create_signup(@cashier, :organizer, @past_event)
    archived_position = @archived_sheet.signup_positions.first
    archived = create_signup(archived_position, :alpha_member, @bake_day)
    archived_slot = slot_of(@archived_sheet.signup_positions.create!(name: "Other"), @bake_day)

    [
      [ :organizer, @bake_day_cashier, @open_slot, {}, true ],
      [ :admin, @ward_cashier, @open_slot, {}, true ],
      [ :alpha_manager, @bake_day_cashier, @open_slot, {}, true ],
      [ :organizer, @bake_day_cashier, ruled, { override_rules: true }, true ],
      [ :organizer, @bake_day_cashier, ruled, {}, false ],
      [ :organizer, @past_signup, @full_slot, {}, false ],
      [ :organizer, own, @open_slot, {}, false ],
      [ :alpha_plain, @bake_day_cashier, @open_slot, {}, false ],
      [ :guardian, @ward_cashier, @open_slot, {}, false ],
      [ :beta_member, @bake_day_cashier, @open_slot, {}, false ],
      [ :admin, archived, archived_slot, {}, false ]
    ].each do |viewer, signup, slot, options, allowed|
      label = "#{viewer} moving #{signup.identifier_name} to #{slot.identifier_name} #{options}"

      assert_equal allowed, moves?(signup, slot) { page_move(viewer, signup, slot, **options) }, "page: #{label}"
      assert_equal allowed, moves?(signup, slot) { move(viewer, signup, slot, **options) }, "tool: #{label}"
    end
  end
end
