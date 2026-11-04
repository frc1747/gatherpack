require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::UpdateSignupTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpSignupsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
    @sheet.update!(cancel_cutoff_hours: 24)
  end

  def update_signup(viewer, signup, **options)
    call_tool("update_signup", user: user(viewer), signup_id: signup.neat_id, **options)
  end

  # The request the viewer's page makes: the member page while SignupPolicy#update?
  # allows it, otherwise the roster.
  def page_update(viewer, signup, **details)
    sign_in user(viewer)
    sheet = signup.signup_sheet
    params = { signup: details }
    if SignupPolicy.new(user(viewer), signup).update?
      patch signup_sheet_signup_path(sheet, signup), params: params
    else
      patch signup_sheet_roster_signup_path(sheet, signup), params: params
    end
    sign_out user(viewer)
  end

  def assert_not_updated(error, viewer, signup, **options)
    before = signup.reload.attributes
    result = assert_refused(error, Signup, AuditLog) { update_signup(viewer, signup, **options) }
    assert_equal before, signup.reload.attributes
    result
  end

  # What the block leaves in these attributes. The change is rolled back.
  def after(signup, *attributes)
    values = nil
    Signup.transaction(requires_new: true) do
      yield
      values = signup.reload.attributes.values_at(*attributes.map(&:to_s))
      raise ActiveRecord::Rollback
    end
    signup.reload
    values
  end

  def past_the_cutoff
    @sheet.update!(cancel_cutoff_hours: 72)
  end

  def relate_to_guardian(name)
    Relationship.create!(parent: person(:guardian), child: person(name), relationship_type: @parent_of, created_by: person(:admin))
  end

  test "a member changes their own sign-up's details; what isn't sent stays" do
    result = update_signup(:alpha_member, @ward_cookies, quantity: 3)

    assert_nil result.error
    assert_equal @ward_cookies, result.changed
    assert_equal [ 3, "Oat" ], [ @ward_cookies.reload.quantity, @ward_cookies.answer ]
    assert_equal [ @ward_cookies.neat_id, "active", 3, "Oat" ], result.value.values_at("id", "status", "quantity", "answer")
    assert_equal [ "Bake Sale", "Bake Day", "Cookies" ], [ result.value.dig("sheet", "title"), result.value.dig("event", "name"), result.value.dig("position", "name") ]

    update_signup(:alpha_member, @ward_cookies, answer: "Rye")
    assert_equal [ 3, "Rye" ], [ @ward_cookies.reload.quantity, @ward_cookies.answer ]
  end

  test "an empty string clears, and a call with nothing to change is refused" do
    assert_nil update_signup(:alpha_member, @ward_cookies, answer: "").error
    assert_equal "", @ward_cookies.reload.answer

    assert_not_updated(/Give at least one of/, :alpha_member, @ward_cookies)
    [ nil, 7 ].each { |bad| assert_not_updated(/note/, :alpha_member, @ward_cookies, note: bad) }
  end

  test "a guardian changes their ward's sign-up" do
    assert_nil update_signup(:guardian, @ward_cashier, note: "Late").error
    assert_equal "Late", @ward_cashier.reload.note
  end

  test "an organizer, an admin and a team manager change any on the sheet, past the cutoff too, and get the roster's row" do
    past_the_cutoff

    result = update_signup(:organizer, @ward_cookies, quantity: 4, note: "Nuts")
    assert_nil result.error
    assert_equal [ 4, "Nuts" ], [ @ward_cookies.reload.quantity, @ward_cookies.note ]
    sheet = call_tool("get_signup_sheet", user: user(:organizer), sheet_id: @sheet.neat_id).value
    row = sheet["events"].flat_map { |event| event["slots"] }.flat_map { |slot| slot["signups"] }.find { |signup| signup["id"] == @ward_cookies.neat_id }
    assert_equal row, result.value.slice(*row.keys)
    assert_equal "Ward World", result.value.dig("on_behalf_of", "name")

    assert_nil update_signup(:admin, @bake_day_cashier, note: "A").error
    assert_nil update_signup(:alpha_manager, @past_signup, note: "B").error
  end

  test "an organizer may change their own or a relative's details, which aren't a mark" do
    own = create_signup(@cashier, :organizer, @cleanup)
    assert_nil update_signup(:organizer, own, note: "Mine").error
    past_the_cutoff
    assert_nil update_signup(:organizer, own, note: "Mine still").error
  end

  test "a plain member is refused, and someone outside the audience doesn't see it" do
    assert_not_updated("Not allowed", :alpha_plain, @bake_day_cashier, note: "x")
    assert_not_updated("Not found", :beta_member, @bake_day_cashier, note: "x")
    assert_not_updated("Not found", :alpha_member, @beta_signup, note: "x")
    assert_equal "denied", McpToolCall.where(tool: "update_signup").order(:created_at).first.outcome
  end

  test "past the cutoff, or once marked, a member is refused and an organizer isn't" do
    past_the_cutoff
    assert_not_updated("Not allowed", :alpha_member, @bake_day_cashier, note: "x")
    assert_not_updated("Not allowed", :guardian, @ward_cashier, note: "x")
    assert_not_updated("Not allowed", :alpha_member, @past_signup, note: "x")
    assert_nil update_signup(:organizer, @bake_day_cashier, note: "x").error
    @sheet.update!(cancel_cutoff_hours: 24)

    marked = create_signup(@cashier, :late, @cleanup, status: :fulfilled)
    assert_not_updated("Not allowed", :late, marked, note: "x")
    assert_nil update_signup(:organizer, marked, note: "x").error
  end

  test "a cancelled sign-up is refused for an organizer with the page's reason, and a member can't" do
    assert_not_updated("This sign-up was cancelled", :organizer, @cancelled, note: "x")
    gone = create_signup(@cashier, :alpha_plain, @cleanup, status: :cancelled)
    assert_not_updated("Not allowed", :alpha_plain, gone, note: "x")
  end

  test "a closed sheet stops members, not organizers; an archived one stops everyone" do
    @sheet.update!(status: :closed)
    assert_not_updated("Not allowed", :alpha_member, @bake_day_cashier, note: "x")
    assert_nil update_signup(:organizer, @bake_day_cashier, note: "x").error

    @sheet.update!(status: :archived)
    assert_not_updated("Not allowed", :organizer, @ward_cashier, note: "x")
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, note: "x")
  end

  test "a quantity on a people position is refused by name, not dropped as the member page does" do
    assert_not_updated("quantity is only for item positions", :alpha_member, @bake_day_cashier, quantity: 2)
    assert_not_updated("quantity is only for item positions", :organizer, @bake_day_cashier, quantity: 2)
  end

  test "capacity and a required answer apply" do
    assert_not_updated(/still needed|full/, :alpha_member, @ward_cookies, quantity: 6)

    @cookies.update!(question_required: true)
    assert_not_updated("Answer \"Flavor?\"", :alpha_member, @ward_cookies, answer: "")
  end

  test "a bad quantity is a refusal, not an internal error" do
    [ 0, -1, 2.5, "two", nil, 2_147_483_648, 99_999_999_999_999, Float::INFINITY ].each do |bad|
      result = assert_not_updated(/quantity/, :admin, @ward_cookies, quantity: bad)
      assert_equal "error", McpToolCall.order(:created_at).last.outcome, "for #{bad.inspect}: #{result.error}"
    end
  end

  test "the largest quantity the column holds doesn't crash on a position with no cap" do
    @cookies.update!(capacity: nil)
    assert_nil update_signup(:admin, @ward_cookies, quantity: 2_147_483_647).error
  end

  test "the page's other fields are refused by name, not dropped" do
    assert_not_updated(/signup_slot_id/, :admin, @bake_day_cashier, note: "x", signup_slot_id: "susl_1")
    assert_not_updated(/status/, :admin, @bake_day_cashier, status: "cancelled")
  end

  test "someone the signer may sign up for can be chosen, and null or empty goes back to the person taking it" do
    relate_to_guardian(:late)

    result = update_signup(:guardian, @ward_cashier, on_behalf_of_id: person(:late).neat_id)
    assert_nil result.error
    assert_equal person(:late), @ward_cashier.reload.on_behalf_of
    assert_equal "Late World", result.value.dig("on_behalf_of", "name")

    [ nil, "" ].each do |back|
      @ward_cashier.update!(on_behalf_of: person(:late))
      result = update_signup(:guardian, @ward_cashier, on_behalf_of_id: back)
      assert_nil result.error
      assert_equal person(:ward), @ward_cashier.reload.on_behalf_of
      assert_equal "Ward World", result.value.dig("on_behalf_of", "name")
    end
  end

  test "someone the signer can't choose is refused; someone they can't see is not found" do
    assert_not_updated("You can't sign up on behalf of #{person(:ward).identifier_name}", :alpha_member, @bake_day_cashier, on_behalf_of_id: person(:ward).neat_id)
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, on_behalf_of_id: person(:beta_member).neat_id)
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, on_behalf_of_id: "per_nonsense")
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, on_behalf_of_id: @alpha.neat_id)
  end

  test "the current on-behalf-of stays allowed, as the form keeps it offered" do
    assert_nil update_signup(:alpha_member, @ward_cookies, on_behalf_of_id: person(:ward).neat_id, note: "Kept").error
    assert_equal [ person(:ward), "Kept" ], [ @ward_cookies.reload.on_behalf_of, @ward_cookies.note ]
  end

  test "an organizer on their own sign-up takes the member page's on-behalf-of check" do
    own = create_signup(@cashier, :organizer, @cleanup)

    assert_not_updated("You can't sign up on behalf of #{person(:ward).identifier_name}", :organizer, own, on_behalf_of_id: person(:ward).neat_id)
    assert_equal [ own.on_behalf_of_id ], after(own, :on_behalf_of_id) { page_update(:organizer, own, on_behalf_of_id: person(:ward).id) }
  end

  test "the roster has no on-behalf-of, so an organizer's change is refused by name where the page drops it" do
    error = "Not allowed: on_behalf_of_id. The roster can't change who takes a sign-up or whose behalf it's on"
    assert_not_updated(error, :organizer, @bake_day_cashier, on_behalf_of_id: person(:ward).neat_id, note: "x")

    page_update(:organizer, @bake_day_cashier, on_behalf_of_id: person(:ward).id, note: "x")
    assert_equal [ person(:alpha_member), "x" ], [ @bake_day_cashier.reload.on_behalf_of, @bake_day_cashier.note ]
  end

  test "the current on-behalf-of stays allowed for someone the viewer can't see, as on the page" do
    signup = create_signup(@cashier, :ward, @cleanup, signed_up_by: person(:guardian), on_behalf_of: person(:beta_member))
    assert_not Pundit.policy_scope!(user(:guardian), Person).exists?(id: person(:beta_member).id)
    expected = [ "Kept", person(:beta_member).id ]

    assert_equal expected, after(signup, :note, :on_behalf_of_id) { page_update(:guardian, signup, on_behalf_of_id: person(:beta_member).id, note: "Kept") }
    assert_equal expected, after(signup, :note, :on_behalf_of_id) { assert_nil update_signup(:guardian, signup, on_behalf_of_id: person(:beta_member).neat_id, note: "Kept").error }
  end

  test "an on-behalf-of just set comes back to a viewer not involved in the sign-up" do
    relate_to_guardian(:late)
    theirs = create_signup(@cashier, :ward, @cleanup)

    result = update_signup(:guardian, theirs, on_behalf_of_id: person(:late).neat_id)

    assert_nil result.error
    assert_equal person(:late), theirs.reload.on_behalf_of
    assert_equal "Late World", result.value.dig("on_behalf_of", "name")
  end

  test "a guardian gives a place to another ward, on the new ward's behalf, as on the page" do
    relate_to_guardian(:late)
    expected = [ person(:late).id, person(:late).id ]

    assert_equal expected, after(@ward_cashier, :person_id, :on_behalf_of_id) { page_update(:guardian, @ward_cashier, person_id: person(:late).id) }

    result = update_signup(:guardian, @ward_cashier, person_id: person(:late).neat_id)
    assert_nil result.error
    assert_equal expected, @ward_cashier.reload.attributes.values_at("person_id", "on_behalf_of_id")
    assert_equal "Late World", result.value.dig("person", "name")
    assert_equal "Late World", result.value.dig("on_behalf_of", "name")
    assert_equal user(:guardian).id.to_s, @ward_cashier.versions.where(event: "update").last.whodunnit
  end

  test "a new taker can come with an on-behalf-of, kept or blank, as on the page" do
    relate_to_guardian(:late)
    late = person(:late)
    ward = person(:ward)

    assert_equal [ late.id, ward.id ], after(@ward_cashier, :person_id, :on_behalf_of_id) { page_update(:guardian, @ward_cashier, person_id: late.id, on_behalf_of_id: ward.id) }
    assert_equal [ late.id, ward.id ], after(@ward_cashier, :person_id, :on_behalf_of_id) { update_signup(:guardian, @ward_cashier, person_id: late.neat_id, on_behalf_of_id: ward.neat_id) }

    assert_equal [ late.id, late.id ], after(@ward_cashier, :person_id, :on_behalf_of_id) { page_update(:guardian, @ward_cashier, person_id: late.id, on_behalf_of_id: "") }
    assert_equal [ late.id, late.id ], after(@ward_cashier, :person_id, :on_behalf_of_id) { update_signup(:guardian, @ward_cashier, person_id: late.neat_id, on_behalf_of_id: nil) }
  end

  test "resending the current taker changes nothing else, even one the viewer can't sign up or see" do
    signup = create_signup(@cashier, :beta_member, @cleanup, signed_up_by: person(:guardian), on_behalf_of: person(:ward))
    assert_not Pundit.policy_scope!(user(:guardian), Person).exists?(id: person(:beta_member).id)
    expected = [ person(:beta_member).id, person(:ward).id, "Kept" ]

    assert_equal expected, after(signup, :person_id, :on_behalf_of_id, :note) { page_update(:guardian, signup, person_id: person(:beta_member).id, note: "Kept") }
    assert_equal expected, after(signup, :person_id, :on_behalf_of_id, :note) { assert_nil update_signup(:guardian, signup, person_id: person(:beta_member).neat_id, note: "Kept").error }
  end

  test "a taker the viewer can't sign up is refused; one they can't see is not found" do
    assert_not_updated("You can't sign up #{person(:ward).identifier_name} on this sheet", :alpha_member, @bake_day_cashier, person_id: person(:ward).neat_id)
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, person_id: person(:beta_member).neat_id)
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, person_id: "per_nonsense")
    assert_not_updated("Not found", :alpha_member, @bake_day_cashier, person_id: @alpha.neat_id)
    assert_equal [ person(:alpha_member).id ], after(@bake_day_cashier, :person_id) { page_update(:alpha_member, @bake_day_cashier, person_id: person(:ward).id) }
  end

  test "a blank person_id is refused by name where the page ignores it" do
    assert_not_updated("person_id can't be blank", :alpha_member, @bake_day_cashier, person_id: "")
    assert_not_updated(/person_id/, :alpha_member, @bake_day_cashier, person_id: nil)
    assert_equal [ person(:alpha_member).id ], after(@bake_day_cashier, :person_id) { page_update(:alpha_member, @bake_day_cashier, person_id: "") }
  end

  test "an organizer on their own sign-up takes the member page's taker check" do
    own = create_signup(@cashier, :organizer, @cleanup)

    assert_not_updated("You can't sign up #{person(:ward).identifier_name} on this sheet", :organizer, own, person_id: person(:ward).neat_id)
    assert_equal [ own.person_id ], after(own, :person_id) { page_update(:organizer, own, person_id: person(:ward).id) }
  end

  test "the roster has no taker, so an organizer's change is refused by name where the page drops it" do
    assert_not_updated("Not allowed: person_id. The roster can't change who takes a sign-up or whose behalf it's on", :organizer, @bake_day_cashier, person_id: person(:late).neat_id, note: "x")

    page_update(:organizer, @bake_day_cashier, person_id: person(:late).id, note: "x")
    assert_equal [ person(:alpha_member), "x" ], [ @bake_day_cashier.reload.person, @bake_day_cashier.note ]
  end

  test "a new taker meets the position's rules and a slot turned off, as on the page" do
    relate_to_guardian(:late)
    license = create_world_badge("License")
    @cashier.signup_position_rules.create!(kind: :badge, badge_ids: [ license.id ])

    assert_equal [ person(:ward).id ], after(@ward_cashier, :person_id) { page_update(:guardian, @ward_cashier, person_id: person(:late).id) }
    result = assert_not_updated(/License|badge/i, :guardian, @ward_cashier, person_id: person(:late).neat_id)
    assert_not_equal "Internal error", result.error

    @cashier.signup_position_rules.destroy_all
    @ward_cashier.signup_slot.update!(disabled: true)
    assert_equal [ person(:ward).id ], after(@ward_cashier, :person_id) { page_update(:guardian, @ward_cashier, person_id: person(:late).id) }
    assert_not_updated("This slot is turned off", :guardian, @ward_cashier, person_id: person(:late).neat_id)
  end

  test "changing the taker sends no email, as on the page" do
    relate_to_guardian(:late)
    clear_enqueued_jobs
    after(@ward_cashier, :person_id) { page_update(:guardian, @ward_cashier, person_id: person(:late).id) }
    assert_nil update_signup(:guardian, @ward_cashier, person_id: person(:late).neat_id).error

    assert_empty enqueued_jobs.select { |job| job[:job] == SendEmailJob }
  end

  test "a member's result leaves out the note and an on-behalf-of they aren't involved in, unless they just set it" do
    theirs = create_signup(@cashier, :ward, @cleanup, on_behalf_of: person(:alpha_plain), note: "Private")

    result = update_signup(:guardian, theirs, answer: "x")
    assert_not result.value.key?("note")
    assert_not result.value.key?("on_behalf_of")
    assert_no_match "Private", result.value.to_json
    assert_no_match "AlphaPlain", result.value.to_json

    result = update_signup(:guardian, theirs, note: "Mine now")
    assert_equal "Mine now", result.value["note"]

    result = update_signup(:ward, theirs, answer: "y")
    assert_equal "AlphaPlain World", result.value.dig("on_behalf_of", "name")
    assert_not result.value.key?("note")
  end

  test "an answer and a note are masked in the call log, stored or refused" do
    update_signup(:alpha_member, @ward_cookies, answer: "Secret flavor", note: "Secret note")
    log = McpToolCall.order(:created_at).last
    assert_equal "ok", log.outcome
    assert_equal [ Mcp::Tool::MASKED, Mcp::Tool::MASKED ], log.arguments.values_at("answer", "note")

    update_signup(:alpha_plain, @ward_cookies, answer: "Secret flavor", note: "Secret note")
    log = McpToolCall.order(:created_at).last
    assert_equal "denied", log.outcome
    assert_no_match "Secret", log.to_json
  end

  test "a read token, the setting being off and the feature being off refuse it" do
    assert_not_updated("Not allowed", :admin, @bake_day_cashier, note: "x", scopes: "mcp_read")
    assert_not_updated("Writes disabled", :admin, @bake_day_cashier, note: "x", writes_enabled: false)
    with_feature(:signups, false) { assert_not_updated("Feature off", :admin, @bake_day_cashier, note: "x") }
  end

  test "the call log and the audit log name the sign-up and the token's user" do
    update_signup(:organizer, @bake_day_cashier, note: "x")
    log = McpToolCall.order(:created_at).last

    assert_equal [ "update_signup", "ok", "Signup", @bake_day_cashier.id ], [ log.tool, log.outcome, log.changed_type, log.changed_id ]
    assert_equal user(:organizer).id.to_s, @bake_day_cashier.versions.where(event: "update").last.whodunnit
  end

  test "hooks run as they do on the page, and it sends no email, as neither page does" do
    clear_enqueued_jobs
    assert_hook_runs("signups - update") { update_signup(:organizer, @bake_day_cashier, note: "x") }
    page_update(:organizer, @bake_day_cashier, note: "y")
    page_update(:alpha_member, @bake_day_cashier, note: "z")

    assert_empty enqueued_jobs.select { |job| job[:job] == SendEmailJob }
  end

  test "details are allowed and refused as the page does" do
    closed = create_signup(@closed_sheet.signup_positions.first, :alpha_member, @bake_day)
    archived = create_signup(@archived_sheet.signup_positions.first, :alpha_member, @bake_day)
    own = create_signup(@cashier, :organizer, @cleanup)

    check = lambda do |cases|
      cases.each do |viewer, signup, allowed|
        label = "#{viewer} on #{signup.identifier_name} on #{signup.signup_sheet.title}"
        expected = allowed ? "Parity" : signup.note

        assert_equal [ expected ], after(signup, :note) { page_update(viewer, signup, note: "Parity") }, "page: #{label}"
        assert_equal [ expected ], after(signup, :note) { update_signup(viewer, signup, note: "Parity") }, "tool: #{label}"
      end
    end

    always = [
      [ :organizer, @bake_day_cashier, true ], [ :alpha_manager, @ward_cashier, true ], [ :admin, @past_signup, true ],
      [ :admin, closed, true ], [ :organizer, own, true ], [ :organizer, @cancelled, false ], [ :admin, archived, false ],
      [ :alpha_plain, @bake_day_cashier, false ], [ :beta_member, @bake_day_cashier, false ], [ :alpha_member, @past_signup, false ],
      [ :alpha_member, closed, false ], [ :alpha_member, archived, false ]
    ]
    check.call(always + [ [ :alpha_member, @bake_day_cashier, true ], [ :guardian, @ward_cashier, true ] ])

    past_the_cutoff
    check.call(always + [ [ :alpha_member, @bake_day_cashier, false ], [ :guardian, @ward_cashier, false ] ])
  end

  test "quantity and on-behalf-of come out as on the page" do
    relate_to_guardian(:late)

    assert_equal [ 3 ], after(@ward_cookies, :quantity) { page_update(:alpha_member, @ward_cookies, quantity: 3) }
    assert_equal [ 3 ], after(@ward_cookies, :quantity) { update_signup(:alpha_member, @ward_cookies, quantity: 3) }
    assert_equal [ 2 ], after(@ward_cookies, :quantity) { page_update(:alpha_member, @ward_cookies, quantity: 6) }
    assert_equal [ 2 ], after(@ward_cookies, :quantity) { update_signup(:alpha_member, @ward_cookies, quantity: 6) }

    assert_equal [ person(:late).id ], after(@ward_cashier, :on_behalf_of_id) { page_update(:guardian, @ward_cashier, on_behalf_of_id: person(:late).id) }
    assert_equal [ person(:late).id ], after(@ward_cashier, :on_behalf_of_id) { update_signup(:guardian, @ward_cashier, on_behalf_of_id: person(:late).neat_id) }
    assert_equal [ person(:alpha_member).id ], after(@bake_day_cashier, :on_behalf_of_id) { page_update(:alpha_member, @bake_day_cashier, on_behalf_of_id: person(:ward).id) }
    assert_equal [ person(:alpha_member).id ], after(@bake_day_cashier, :on_behalf_of_id) { update_signup(:alpha_member, @bake_day_cashier, on_behalf_of_id: person(:ward).neat_id) }
  end
end
