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

  test "a member sees a teammate's sign-up only where names are shown, never notes" do
    result = signups(:ward, :alpha_member)

    assert_equal [ [ "Bake Sale", "Cashier" ], [ "Bake Sale", "Cookies" ] ], labels(result).sort
    assert result.value["items"].none? { |item| item.key?("note") }
  end

  test "a sign-up taken for a teammate on someone's behalf isn't shown under the one it's on behalf of" do
    other = call_tool("person_signups", user: user(:alpha_manager), person_id: person(:ward).neat_id)

    assert_equal [ "Cashier" ], other.value["items"].map { |item| item["position"]["name"] }.first(1)
    assert_equal [ "AlphaMember World" ], other.value["items"].select { |item| item["position"]["name"] == "Cookies" }.map { |item| item["person"]["name"] }
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
end
