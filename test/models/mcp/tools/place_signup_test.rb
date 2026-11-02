require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::PlaceSignupTest < ActionDispatch::IntegrationTest
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

  def place(viewer, taker, slot = @open_slot, **options)
    call_tool("place_signup", user: user(viewer), slot_id: slot.neat_id, person_id: person(taker).neat_id, **options)
  end

  def emails_from
    clear_enqueued_jobs
    yield
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args][1..3] }.sort
  end

  def rule_on(position)
    license = create_world_badge("License")
    position.signup_position_rules.create!(kind: :badge, badge_ids: [ license.id ])
    license
  end

  # The request the viewer's page makes: organizers place from the roster,
  # everyone else from the member page.
  def page_place(viewer, taker, slot, **details)
    sheet = slot.signup_sheet
    params = { signup: { signup_slot_id: slot.id, person_id: person(taker).id, **details } }
    if sheet.organizer?(person(viewer)) && !sheet.archived?
      post signup_sheet_roster_signups_path(sheet), params: params
    else
      post signup_sheet_signups_path(sheet), params: params
    end
  end

  test "an organizer places a person and gets the sign-up back" do
    result = place(:organizer, :alpha_plain)

    signup = Signup.find_by!(signup_slot: @open_slot, person: person(:alpha_plain))
    assert_equal signup, result.changed
    assert_equal [ person(:organizer), person(:alpha_plain) ], [ signup.signed_up_by, signup.on_behalf_of ]
    assert_equal [ signup.neat_id, "active" ], result.value.values_at("id", "status")
    assert_equal person(:alpha_plain).neat_id, result.value.dig("person", "id")
    assert_equal person(:alpha_plain).neat_id, result.value.dig("on_behalf_of", "id")
    assert_equal "Bake Sale", result.value.dig("sheet", "title")
    assert_equal "Clean-up", result.value.dig("event", "name")
    assert_equal "Cashier", result.value.dig("position", "name")
  end

  test "an admin and a team manager are organizers too" do
    assert_difference("Signup.count", 2) do
      assert_nil place(:admin, :alpha_plain).error
      assert_nil place(:alpha_manager, :late).error
    end
  end

  test "an organizer places on a draft or closed sheet, and not an archived one" do
    assert_nil place(:admin, :alpha_plain, slot_of(@draft_sheet.signup_positions.first, @bake_day)).error
    assert_nil place(:admin, :alpha_plain, slot_of(@closed_sheet.signup_positions.first, @bake_day)).error
    assert_refused("Not allowed", Signup) { place(:admin, :alpha_plain, slot_of(@archived_sheet.signup_positions.first, @bake_day)) }
  end

  test "an organizer can place only someone the sheet is open to" do
    assert_refused("Person must be someone the sheet is open to", Signup) { place(:admin, :beta_member) }
    assert_equal "error", McpToolCall.order(:created_at).last.outcome
  end

  test "an audience member places themselves" do
    signup = Signup.find(place(:alpha_plain, :alpha_plain).changed.id)

    assert_equal [ person(:alpha_plain) ] * 3, [ signup.person, signup.signed_up_by, signup.on_behalf_of ]
  end

  test "a relative places the person they may sign up, who needn't be in their person scope" do
    assert_nil mcp_context(user(:guardian)).policy_scope(Person).find_by(id: person(:ward).id)

    signup = place(:guardian, :ward).changed

    assert_equal [ person(:ward), person(:guardian), person(:ward) ], [ signup.person, signup.signed_up_by, signup.on_behalf_of ]
  end

  test "a member can't place a teammate they aren't related to" do
    assert_refused("Not allowed", Signup) { place(:alpha_plain, :alpha_member) }
    assert_equal "denied", McpToolCall.order(:created_at).last.outcome
  end

  test "someone outside the audience is refused" do
    assert_refused("Not found", Signup) { place(:beta_member, :beta_member) }
    assert_refused("Not found", Signup) { place(:beta_member, :alpha_member) }
    assert_refused("Not allowed", Signup) { place(:guardian, :guardian) }
  end

  test "a member can't place on a closed sheet or reach a draft" do
    assert_refused("Not allowed", Signup) { place(:alpha_plain, :alpha_plain, slot_of(@closed_sheet.signup_positions.first, @bake_day)) }
    assert_refused("Not found", Signup) { place(:alpha_plain, :alpha_plain, slot_of(@draft_sheet.signup_positions.first, @bake_day)) }
  end

  test "a person the viewer can't see is not found" do
    assert_refused("Not found", Signup) { place(:alpha_plain, :beta_member) }
  end

  test "a full slot is refused for an organizer and a member" do
    assert_refused("This slot is full", Signup) { place(:organizer, :alpha_plain, @full_slot) }
    assert_refused("This slot is full", Signup) { place(:alpha_plain, :alpha_plain, @full_slot) }
  end

  test "a failing rule is refused and no one can override it, though the roster can" do
    rule_on(@cashier)
    message = "Needs the License badge"

    assert_refused(message, Signup) { place(:alpha_plain, :alpha_plain) }
    assert_refused(message, Signup) { place(:organizer, :alpha_plain) }
    assert_refused(message, Signup) { place(:admin, :alpha_plain, override_rules: true) }
    assert_not_includes Mcp.tool("place_signup").argument_names, "override_rules"

    assert page_changes_rows?(Signup, as: user(:organizer)) { page_place(:organizer, :alpha_plain, @open_slot, override_rules: "1") }
  end

  test "a person who meets the rule is placed" do
    license = rule_on(@cashier)
    BadgeAssignment.create!(badge: license, person: person(:alpha_plain))

    assert_nil place(:alpha_plain, :alpha_plain).error
  end

  test "a slot turned off is not found for a member and refused for an organizer" do
    @open_slot.update!(disabled: true)

    assert_refused("Not found", Signup) { place(:alpha_plain, :alpha_plain) }
    assert_refused("This slot is turned off", Signup) { place(:organizer, :alpha_plain) }
  end

  test "an item position or a required question can't be taken, having no way to give them" do
    question = @sheet.signup_positions.create!(name: "Driver", question: "Which car?", question_required: true)

    assert_refused("Quantity is needed", Signup) { place(:alpha_plain, :alpha_plain, slot_of(@cookies, @cleanup)) }
    assert_refused("Answer \"Which car?\"", Signup) { place(:alpha_plain, :alpha_plain, slot_of(question, @cleanup)) }
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "susl_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", Signup) { call_tool("place_signup", user: user(:admin), slot_id: bad, person_id: person(:ward).neat_id) }
    end
    [ "nonsense", "per_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", Signup) { call_tool("place_signup", user: user(:admin), slot_id: @open_slot.neat_id, person_id: bad) }
    end
    assert_refused(/person_id/, Signup) { call_tool("place_signup", user: user(:admin), slot_id: @open_slot.neat_id) }
  end

  test "a read token, the setting being off and the feature being off refuse it" do
    assert_refused("Not allowed", Signup) { place(:admin, :alpha_plain, scopes: "mcp_read") }
    assert_refused("Writes disabled", Signup) { place(:admin, :alpha_plain, writes_enabled: false) }
    with_feature(:signups, false) { assert_refused("Feature off", Signup) { place(:admin, :alpha_plain) } }
  end

  test "the call log records the sign-up" do
    signup = place(:organizer, :alpha_plain).changed
    log = McpToolCall.order(:created_at).last

    assert_equal [ "place_signup", "ok", "Signup", signup.id ], [ log.tool, log.outcome, log.changed_type, log.changed_id ]
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("signups - create") { place(:organizer, :alpha_plain) }
  end

  test "the confirmation and reminder go out as they do on the page" do
    [ [ :organizer, :alpha_plain ], [ :guardian, :ward ], [ :alpha_plain, :alpha_plain ] ].each do |viewer, taker|
      sign_in user(viewer)
      page = emails_from { page_place(viewer, taker, @open_slot) }
      sign_out user(viewer)
      Signup.find_by!(signup_slot: @open_slot, person: person(taker)).destroy!

      tool = nil
      emails = emails_from { tool = place(viewer, taker) }

      assert_equal [ viewer, taker ].uniq.map { |name| user(name).email }.sort, emails.map(&:first)
      assert_equal page, emails, "#{viewer} placing #{taker}"
      assert_enqueued_with(job: SignupReminderJob)
      tool.changed.destroy!
    end
  end

  test "it allows and refuses as the page does" do
    rule_slot = @sheet.signup_positions.create!(name: "Bartender").tap { |position| rule_on(position) }.signup_slots.find_by!(event: @cleanup)
    off_slot = @sheet.signup_positions.create!(name: "Off").signup_slots.find_by!(event: @cleanup).tap { |slot| slot.update!(disabled: true) }
    draft_slot = slot_of(@draft_sheet.signup_positions.first, @bake_day)
    closed_slot = slot_of(@closed_sheet.signup_positions.first, @bake_day)
    archived_slot = slot_of(@archived_sheet.signup_positions.first, @bake_day)
    [
      [ :admin, :alpha_plain, @open_slot, true ],
      [ :admin, :beta_member, @open_slot, false ],
      [ :organizer, :alpha_plain, @open_slot, true ],
      [ :organizer, :alpha_plain, @full_slot, false ],
      [ :organizer, :alpha_plain, rule_slot, false ],
      [ :organizer, :alpha_plain, off_slot, false ],
      [ :alpha_manager, :late, @open_slot, true ],
      [ :admin, :alpha_plain, draft_slot, true ],
      [ :admin, :alpha_plain, closed_slot, true ],
      [ :admin, :alpha_plain, archived_slot, false ],
      [ :alpha_plain, :alpha_plain, @open_slot, true ],
      [ :alpha_plain, :alpha_plain, @full_slot, false ],
      [ :alpha_plain, :alpha_plain, rule_slot, false ],
      [ :alpha_plain, :alpha_plain, off_slot, false ],
      [ :alpha_plain, :alpha_plain, draft_slot, false ],
      [ :alpha_plain, :alpha_plain, closed_slot, false ],
      [ :alpha_plain, :alpha_member, @open_slot, false ],
      [ :guardian, :ward, @open_slot, true ],
      [ :guardian, :guardian, @open_slot, false ],
      [ :beta_member, :beta_member, @open_slot, false ],
      [ :beta_member, :alpha_member, @open_slot, false ]
    ].each do |viewer, taker, slot, allowed|
      label = "#{viewer} placing #{taker} in #{slot.identifier_name} on #{slot.signup_sheet.title}"

      assert_equal allowed, page_changes_rows?(Signup, as: user(viewer)) { page_place(viewer, taker, slot) }, "page: #{label}"
      assert_equal allowed, changes_rows?(Signup) { place(viewer, taker, slot) }, "tool: #{label}"
    end
  end
end
