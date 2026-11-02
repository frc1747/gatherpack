require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::RemoveSignupTest < ActionDispatch::IntegrationTest
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
    clear_enqueued_jobs
  end

  def remove(viewer, signup, **options)
    call_tool("remove_signup", user: user(viewer), signup_id: signup.neat_id, **options)
  end

  # The call is refused with this error and the sign-up is left as it was.
  def assert_not_removed(error, viewer, signup, **options)
    before = signup.reload.attributes
    result = assert_refused(error, Signup) { remove(viewer, signup, **options) }
    assert_equal before, signup.reload.attributes
    result
  end

  def emails_from
    clear_enqueued_jobs
    yield
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args][1..3] }.sort
  end

  # The request the viewer's page makes: organizers cancel from the roster,
  # everyone else from the member page.
  def page_remove(viewer, signup)
    sheet = signup.signup_sheet
    if sheet.organizer?(person(viewer)) && !sheet.archived?
      delete signup_sheet_roster_signup_path(sheet, signup)
    else
      delete signup_sheet_signup_path(sheet, signup)
    end
  end

  # Whether the block cancels the sign-up. The change is rolled back.
  def cancels?(signup)
    cancelled = false
    Signup.transaction(requires_new: true) do
      yield
      cancelled = signup.reload.cancelled?
      raise ActiveRecord::Rollback
    end
    signup.reload
    cancelled
  end

  def past_the_cutoff
    @sheet.update!(cancel_cutoff_hours: 72)
  end

  test "it is marked destructive" do
    assert Mcp.tool("remove_signup").annotations[:destructive_hint]
  end

  test "an organizer cancels a sign-up and gets it back; it stays on the roster" do
    result = nil
    assert_no_difference("Signup.count") { result = remove(:organizer, @bake_day_cashier) }

    assert @bake_day_cashier.reload.cancelled?
    assert_equal @bake_day_cashier, result.changed
    assert_equal [ @bake_day_cashier.neat_id, "cancelled" ], result.value.values_at("id", "status")
    assert_equal person(:alpha_member).neat_id, result.value.dig("person", "id")
    assert_equal "Bake Sale", result.value.dig("sheet", "title")
    assert_equal "Bake Day", result.value.dig("event", "name")
    assert_equal "Cashier", result.value.dig("position", "name")
  end

  test "an admin and a team manager are organizers too" do
    assert_nil remove(:admin, @bake_day_cashier).error
    assert_nil remove(:alpha_manager, @ward_cashier).error
  end

  test "signed_up_by is never returned, as no sign-up page names the signer" do
    assert_not remove(:organizer, @ward_cashier).value.key?("signed_up_by")
    assert_not remove(:alpha_plain, @quiet_made).value.key?("signed_up_by")
  end

  test "signed_up_by is not returned to the taker of a sign-up someone else made, nor to a relative who didn't make it" do
    assert_not remove(:late, @quiet_made).value.key?("signed_up_by")

    by_ward = create_signup(@cashier, :ward, @cleanup)
    assert_not remove(:guardian, by_ward).value.key?("signed_up_by")
  end

  test "a member cancels their own sign-up" do
    assert_nil remove(:alpha_member, @bake_day_cashier).error
    assert @bake_day_cashier.reload.cancelled?
  end

  test "a relative cancels a sign-up of the person they may sign up, and one who made a sign-up cancels it" do
    assert_nil remove(:guardian, @ward_cashier).error
    assert_nil remove(:alpha_plain, @quiet_made).error
  end

  test "on_behalf_of goes to organizers and those involved, not a relative the tool is narrower for" do
    sheet = create_signups_sheet("Anyone Sale", @alpha, [ @cleanup ], on_behalf_of_mode: :anyone, others_relationship_type_ids: [ @parent_of.id ])
    slot = sheet.signup_positions.create!(name: "Helper").signup_slots.find_by!(event: @cleanup)
    sign_in user(:ward)
    post signup_sheet_signups_path(sheet), params: { signup: { signup_slot_id: slot.id, person_id: person(:ward).id, on_behalf_of_id: person(:alpha_plain).id } }
    sign_out user(:ward)
    signup = Signup.find_by!(signup_slot: slot, person: person(:ward), on_behalf_of: person(:alpha_plain))

    sign_in user(:guardian)
    get signup_sheet_path(sheet)
    assert_response :success
    assert_no_match "AlphaPlain", response.body
    sign_out user(:guardian)

    result = remove(:guardian, signup)
    assert_nil result.error
    assert_equal "Ward World", result.value.dig("person", "name")
    assert_not result.value.key?("on_behalf_of")
    assert_no_match "AlphaPlain", result.value.to_json

    signup.update_columns(status: Signup.statuses[:active])
    assert_equal "AlphaPlain World", remove(:ward, signup).value.dig("on_behalf_of", "name")

    signup.update_columns(status: Signup.statuses[:active])
    assert_equal "AlphaPlain World", remove(:alpha_manager, signup).value.dig("on_behalf_of", "name")
  end

  test "on_behalf_of is who the sign-up is on behalf of, not the person taking it" do
    result = remove(:alpha_member, @ward_cookies)
    assert_equal person(:alpha_member).neat_id, result.value.dig("person", "id")
    assert_equal person(:ward).neat_id, result.value.dig("on_behalf_of", "id")

    @ward_cookies.update_columns(status: Signup.statuses[:active])
    result = remove(:organizer, @ward_cookies)
    assert_equal person(:ward).neat_id, result.value.dig("on_behalf_of", "id")
    assert_equal person(:alpha_member).neat_id, result.value.dig("person", "id")
  end

  test "a member can't cancel someone else's sign-up" do
    assert_not_removed("Not allowed", :alpha_plain, @bake_day_cashier)
    assert_equal "denied", McpToolCall.order(:created_at).last.outcome
  end

  test "someone outside the audience is refused" do
    assert_not_removed("Not found", :beta_member, @bake_day_cashier)
    assert_not_removed("Not found", :alpha_member, @beta_signup)
  end

  test "past the cutoff a member is refused and an organizer isn't, as on the page" do
    past_the_cutoff

    assert_not_removed("Not allowed", :alpha_member, @bake_day_cashier)
    assert_not_removed("Not allowed", :guardian, @ward_cashier)
    assert_nil remove(:organizer, @bake_day_cashier).error
    assert @bake_day_cashier.reload.cancelled?
  end

  test "a sign-up whose event has started is past any cutoff" do
    assert_not_removed("Not allowed", :alpha_member, @past_signup)
    assert_nil remove(:organizer, @past_signup).error
  end

  test "a cancelled sign-up can't be cancelled again" do
    assert_not_removed("AlphaManager World's sign-up was already cancelled", :organizer, @cancelled)

    gone = create_signup(@cashier, :alpha_plain, @cleanup, status: :cancelled)
    assert_not_removed("Not allowed", :alpha_plain, gone)
  end

  test "an organizer cancels a sign-up that was marked; a member can't" do
    @past_signup.update!(status: :fulfilled)

    assert_not_removed("Not allowed", :alpha_member, @past_signup)
    assert_nil remove(:organizer, @past_signup).error
  end

  test "a closed sheet stops members, not organizers; an archived one stops everyone" do
    @sheet.update!(status: :closed)
    assert_not_removed("Not allowed", :alpha_member, @bake_day_cashier)
    assert_nil remove(:organizer, @bake_day_cashier).error

    @sheet.update!(status: :archived)
    assert_not_removed("Not allowed", :organizer, @ward_cashier)
    assert_not_removed("Not found", :alpha_member, @past_signup)
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "sup_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", Signup) { call_tool("remove_signup", user: user(:admin), signup_id: bad) }
    end
    assert_refused(/signup_id/, Signup) { call_tool("remove_signup", user: user(:admin)) }
  end

  test "a read token, the setting being off and the feature being off refuse it" do
    assert_not_removed("Not allowed", :admin, @bake_day_cashier, scopes: "mcp_read")
    assert_not_removed("Writes disabled", :admin, @bake_day_cashier, writes_enabled: false)
    with_feature(:signups, false) { assert_not_removed("Feature off", :admin, @bake_day_cashier) }
  end

  test "the call log records the sign-up" do
    remove(:organizer, @bake_day_cashier)
    log = McpToolCall.order(:created_at).last

    assert_equal [ "remove_signup", "ok", "Signup", @bake_day_cashier.id ], [ log.tool, log.outcome, log.changed_type, log.changed_id ]
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("signups - cancelled") { remove(:organizer, @bake_day_cashier) }
  end

  test "an organizer's cancel sends the people on it the roster's email" do
    sign_in user(:organizer)
    page = emails_from { page_remove(:organizer, @ward_cashier) }
    sign_out user(:organizer)
    assert @ward_cashier.reload.cancelled?
    @ward_cashier.update_columns(status: Signup.statuses[:active])

    emails = emails_from { assert_nil remove(:organizer, @ward_cashier).error }

    assert_equal [ user(:guardian).email, user(:ward).email ].sort, emails.map(&:first)
    assert_match "Sign-up cancelled: Cashier, Bake Day", emails.first[1]
    assert_equal page, emails
  end

  test "an organizer cancelling their own sign-up gets the roster's email" do
    own = create_signup(@cashier, :organizer, @cleanup)

    emails = emails_from { assert_nil remove(:organizer, own).error }

    assert_equal [ user(:organizer).email ], emails.map(&:first)
    assert_match "Organizer World cancelled Organizer World&#39;s sign-up", emails.first[2]
  end

  test "a member's cancel sends no email, as on the page" do
    sign_in user(:guardian)
    assert_empty(emails_from { page_remove(:guardian, @ward_cashier) })
    sign_out user(:guardian)
    assert @ward_cashier.reload.cancelled?

    assert_empty(emails_from { assert_nil remove(:alpha_member, @bake_day_cashier).error })
  end

  test "a refusal sends no email" do
    assert_empty(emails_from { remove(:alpha_plain, @bake_day_cashier) })
    assert_empty(emails_from { remove(:organizer, @cancelled) })
  end

  test "it allows and refuses as the page does" do
    archived_signup = create_signup(@archived_sheet.signup_positions.first, :alpha_member, @bake_day)
    closed_signup = create_signup(@closed_sheet.signup_positions.first, :alpha_member, @bake_day)
    fulfilled = create_signup(@cashier, :late, @cleanup, status: :fulfilled)

    check = lambda do |cases|
      cases.each do |viewer, signup, allowed|
        label = "#{viewer} cancelling #{signup.identifier_name} on #{signup.signup_sheet.title}"
        page = cancels?(signup) do
          sign_in user(viewer)
          page_remove(viewer, signup)
          sign_out user(viewer)
        end

        assert_equal allowed, page, "page: #{label}"
        assert_equal allowed, cancels?(signup) { remove(viewer, signup) }, "tool: #{label}"
      end
    end

    organizers = [
      [ :admin, @bake_day_cashier, true ], [ :organizer, @bake_day_cashier, true ], [ :alpha_manager, @ward_cashier, true ],
      [ :organizer, fulfilled, true ], [ :admin, @past_signup, true ], [ :admin, closed_signup, true ], [ :admin, archived_signup, false ]
    ]
    refused = [
      [ :alpha_plain, @bake_day_cashier, false ], [ :beta_member, @bake_day_cashier, false ], [ :alpha_member, @beta_signup, false ],
      [ :late, fulfilled, false ], [ :alpha_member, @past_signup, false ], [ :alpha_member, closed_signup, false ], [ :alpha_member, archived_signup, false ]
    ]
    members = [ [ :alpha_member, @bake_day_cashier ], [ :guardian, @ward_cashier ] ]
    check.call(organizers + refused + members.map { |viewer, signup| [ viewer, signup, true ] })

    past_the_cutoff
    check.call(organizers + refused + members.map { |viewer, signup| [ viewer, signup, false ] })
  end
end
