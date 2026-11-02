require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::PersonSignupsTest < ActiveSupport::TestCase
  include McpWorld
  include McpSignupsWorld

  setup do
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
  end

  def signups(viewer, person)
    call_tool("person_signups", user: user(viewer), person_id: person(person).neat_id)
  end

  def labels(result)
    result.value["items"].map { |item| [ item["sheet"]["title"], item["position"]["name"] ] }
  end

  test "an admin sees a person's upcoming sign-ups, soonest first, with those on their behalf" do
    result = signups(:admin, :ward)

    assert_equal [ [ "Bake Sale", "Cashier" ], [ "Bake Sale", "Cookies" ] ], labels(result)
    item = result.value["items"].last
    assert_equal [ "AlphaMember World", "Ward World", "Oat", 2 ], [ item["person"]["name"], item["on_behalf_of"]["name"], item["answer"], item["quantity"] ]
    assert_equal "Bake Day", item["event"]["name"]
  end

  test "signed_up_by is never returned, to organizers or those involved" do
    [ [ :admin, :ward ], [ :admin, :alpha_member ], [ :alpha_member, :alpha_member ] ].each do |viewer, subject|
      items = signups(viewer, subject).value["items"]
      assert items.any?
      assert items.none? { |item| item.key?("signed_up_by") }
    end
  end

  test "past and cancelled sign-ups are left out" do
    assert_equal [ [ "Bake Sale", "Cashier" ], [ "Bake Sale", "Cookies" ], [ "Quiet Sale", "Helper" ] ], labels(signups(:admin, :alpha_member)).sort
    assert_empty signups(:admin, :alpha_manager).value["items"]
  end

  test "organizers see notes" do
    first = signups(:organizer, :alpha_member).value["items"].find { |item| item["position"]["name"] == "Cashier" }

    assert_equal "Bring change", first["note"]
  end

  test "a team manager sees their team's members' sign-ups" do
    assert_equal 2, signups(:alpha_manager, :ward).value["items"].size
  end

  test "a plain teammate sees a sign-up only under the person who takes the place, without on-behalf-of or notes" do
    alpha_member = signups(:alpha_plain, :alpha_member)
    ward = signups(:alpha_plain, :ward)

    assert_equal [ [ "Bake Sale", "Cashier" ], [ "Bake Sale", "Cookies" ] ], labels(alpha_member).sort
    assert((alpha_member.value["items"] + ward.value["items"]).none? { |item| item.key?("on_behalf_of") || item.key?("note") })
    assert_equal [ [ "Bake Sale", "Cashier" ] ], labels(ward)
  end

  test "a names-for-organizers sheet hides a teammate's sign-up from a plain member" do
    assert_not_includes labels(signups(:alpha_plain, :alpha_member)), [ "Quiet Sale", "Helper" ]
  end

  test "a plain teammate doesn't see a no-show or any status; organizers do" do
    assert_empty signups(:alpha_plain, :late).value["items"].reject { |item| item["sheet"]["title"] == "Quiet Sale" }
    assert_equal [ "no_show", "active" ], signups(:admin, :late).value["items"].map { |item| item["status"] }
    assert signups(:alpha_plain, :alpha_member).value["items"].none? { |item| item.key?("status") }
    assert_equal [ "active" ], signups(:alpha_member, :alpha_member).value["items"].map { |item| item["status"] }.uniq
  end

  test "someone who made a sign-up sees it even where names are hidden" do
    assert_equal [ [ "Quiet Sale", "Helper" ] ], labels(signups(:alpha_plain, :late))
    assert_empty signups(:ward, :late).value["items"]
  end

  test "a turned-off slot's sign-up is hidden from a plain teammate, kept for organizers and the person" do
    @bake_day_cashier.signup_slot.update!(disabled: true)

    assert_equal [ [ "Bake Sale", "Cookies" ] ], labels(signups(:alpha_plain, :alpha_member))
    assert_includes labels(signups(:alpha_manager, :alpha_member)), [ "Bake Sale", "Cashier" ]
    assert_includes labels(signups(:alpha_member, :alpha_member)), [ "Bake Sale", "Cashier" ]
  end

  test "an event with no time set is upcoming for its whole day and flagged" do
    day = create_signups_event("Date Only", @alpha, Time.utc(2026, 3, 12, 0, 0)).tap { |event| event.update!(end_time: Time.utc(2026, 3, 12, 23, 59)) }
    @sheet.signup_sheet_events.create!(event: day)
    @sheet.sync_slots!
    create_signup(@cashier, :alpha_manager, day)

    item = signups(:admin, :alpha_manager).value["items"].first
    assert_equal [ "Date Only", true ], [ item["event"]["name"], item["event"]["time_unset"] ]
    assert_equal false, signups(:admin, :ward).value["items"].first["event"]["time_unset"]
  end

  test "a person sees their own sign-ups, on a names-for-organizers sheet too" do
    assert_includes labels(signups(:alpha_member, :alpha_member)), [ "Quiet Sale", "Helper" ]
  end

  test "a person on behalf of whom a sign-up is made sees it" do
    item = signups(:ward, :ward).value["items"].find { |i| i["position"]["name"] == "Cookies" }

    assert_equal "Ward World", item.dig("on_behalf_of", "name")
  end

  test "a plain member on another team doesn't find the person" do
    assert_equal "Not found", signups(:beta_member, :alpha_member).error
  end

  test "a guardian in no team doesn't find their ward" do
    assert_equal "Not found", signups(:guardian, :ward).error
    assert_equal [], signups(:guardian, :guardian).value["items"]
  end

  test "sign-ups on a sheet the viewer can't see are left out" do
    @sheet.update!(status: :draft)

    assert_empty signups(:ward, :alpha_member).value["items"].select { |item| item["sheet"]["title"] == "Bake Sale" }
    assert_equal 2, signups(:organizer, :ward).value["items"].size
  end

  test "archived sheets are left out for everyone" do
    @sheet.archived!

    assert_empty signups(:admin, :ward).value["items"]
  end

  test "a limit truncates" do
    result = call_tool("person_signups", user: user(:admin), person_id: person(:ward).neat_id, limit: 1)

    assert_equal 1, result.value["items"].size
    assert result.value["truncated"]
  end

  test "feature off means the tool is neither listed nor callable" do
    with_feature(:signups, false) do
      refute_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "person_signups"
      assert_equal "Feature off", signups(:admin, :ward).error
    end
  end

  test "an event that has started but not ended is not upcoming" do
    travel_to Time.utc(2026, 3, 14, 11, 0)
    assert_empty signups(:admin, :ward).value["items"]
    assert_empty signups(:admin, :alpha_member).value["items"].select { |item| item["event"]["name"] == "Bake Day" }
  end
end
