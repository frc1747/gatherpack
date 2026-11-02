require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::GetSignupSheetTest < ActiveSupport::TestCase
  include McpWorld
  include McpSignupsWorld

  setup do
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
  end

  def get(viewer, sheet = @sheet, **args)
    call_tool("get_signup_sheet", user: user(viewer), sheet_id: sheet.neat_id, **args)
  end

  def slot(value, event, position)
    value["events"].find { |item| item["event"]["name"] == event }["slots"].find { |item| item["position"]["name"] == position }
  end

  def holders(value, event, position)
    slot(value, event, position)["signups"].map { |signup| signup["person"]["name"] }
  end

  test "the sheet, its events and slots come in page order" do
    value = get(:alpha_member).value

    assert_equal [ "Bake Sale", "open", "Bring a smile", "organizer@example.com" ], value.values_at("title", "status", "description", "contact")
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, value["team"])
    assert_equal [ "Past Sale", "Bake Day", "Clean-up" ], value["events"].map { |item| item["event"]["name"] }
    assert_equal [ "Cashier", "Cookies" ], value["events"][1]["slots"].map { |item| item["position"]["name"] }
  end

  test "places are counted for every viewer" do
    cashier = slot(get(:alpha_member).value, "Bake Day", "Cashier")
    cookies = slot(get(:alpha_member).value, "Bake Day", "Cookies")

    assert_equal [ 2, 2, 0, true ], cashier.values_at("capacity", "filled", "open", "full")
    assert_equal [ 5, 2, 3, false ], cookies.values_at("capacity", "filled", "open", "full")
    assert_equal({ "id" => @cookies.neat_id, "name" => "Cookies", "kind" => "items", "description" => nil, "unit" => "dozen" }, cookies["position"])
  end

  test "an audience member sees who holds each place, with answers and quantities, but no notes or on-behalf-of" do
    value = get(:alpha_member).value

    assert value["names_visible"]
    assert_not value["organizer"]
    assert_equal [ "AlphaMember World", "Ward World" ], holders(value, "Bake Day", "Cashier")
    cookie = slot(value, "Bake Day", "Cookies")["signups"].first
    assert_equal [ "Oat", 2, "AlphaMember World" ], [ cookie["answer"], cookie["quantity"], cookie["person"]["name"] ]
    assert_not_includes cookie.keys, "on_behalf_of"
    assert(value["events"].flat_map { |e| e["slots"] }.flat_map { |s| s["signups"] }.none? { |signup| signup.key?("note") })
  end

  test "cancelled sign-ups are not listed to members, and not counted" do
    assert_empty slot(get(:alpha_member).value, "Clean-up", "Cashier")["signups"]
    assert_equal [ 0, 2 ], slot(get(:alpha_member).value, "Clean-up", "Cashier").values_at("filled", "open")
  end

  test "names for organizers only hides every name from members, but counts stay" do
    value = get(:alpha_member, @quiet_sheet).value
    helper = slot(value, "Bake Day", "Helper")

    assert_not value["names_visible"]
    assert_empty helper["signups"]
    assert_equal 2, helper["filled"]
    assert_nil helper["open"]
  end

  test "organizers see the roster: every status, notes and on-behalf-of" do
    [ :admin, :alpha_manager, :organizer ].each do |viewer|
      value = get(viewer).value

      assert value["organizer"], viewer
      assert_equal [ "AlphaMember World", "Ward World" ], holders(value, "Bake Day", "Cashier"), viewer
      assert_equal "Bring change", slot(value, "Bake Day", "Cashier")["signups"].first["note"]
      assert_equal "Ward World", slot(value, "Bake Day", "Cookies")["signups"].first.dig("on_behalf_of", "name")
      assert_equal [ "cancelled" ], slot(value, "Clean-up", "Cashier")["signups"].map { |signup| signup["status"] }
    end
  end

  test "a team manager sees names on a names-for-organizers sheet; a listed organizer of another sheet doesn't" do
    assert_equal [ "AlphaMember World", "Late World" ], holders(get(:alpha_manager, @quiet_sheet).value, "Bake Day", "Helper")
    assert_empty holders(get(:organizer, @quiet_sheet).value, "Bake Day", "Helper")
  end

  test "someone outside the audience doesn't find the sheet" do
    assert_equal "Not found", get(:beta_member).error
    assert_equal "Not found", get(:beta_member, @quiet_sheet).error
  end

  test "drafts are hidden from members, closed sheets stay visible as on the page, organizers see both" do
    assert_equal "Not found", get(:alpha_member, @draft_sheet).error
    assert_equal "closed", get(:alpha_member, @closed_sheet).value["status"]
    assert_equal "Not found", get(:organizer, @draft_sheet).error
    assert_equal "draft", get(:alpha_manager, @draft_sheet).value["status"]
  end

  test "an archived sheet is shown to organizers only" do
    assert_equal "Not found", get(:alpha_member, @archived_sheet).error
    assert_equal "archived", get(:admin, @archived_sheet).value["status"]
  end

  test "another team's organizer doesn't find the sheet" do
    assert_equal "Not found", get(:beta_member, @draft_sheet).error
    assert_equal "Beta Sale", get(:beta_member, @beta_sheet).value["title"]
  end

  test "a relative sees the sheet, the names, and their own sign-up, but not who made it" do
    value = get(:guardian).value

    assert value["names_visible"]
    assert_equal [ "AlphaMember World", "Ward World" ], holders(value, "Bake Day", "Cashier")
    mine = value["my_signups"].first
    assert_equal [ 1, "Ward World", "Ward World", "Cashier", "active" ],
      [ value["my_signups"].size, mine["person"]["name"], mine["on_behalf_of"]["name"], mine["position"]["name"], mine["status"] ]
    assert_not_includes mine.keys, "signed_up_by"
    assert_not_includes mine.to_s, "Guardian World"
  end

  test "the person a sign-up is on behalf of sees it in their own sign-ups" do
    value = get(:ward).value

    assert_equal [ "Cashier", "Cookies" ], value["my_signups"].map { |signup| signup["position"]["name"] }
    assert_equal [ "AlphaMember World" ], value["my_signups"].map { |signup| signup["person"]["name"] }.uniq - [ "Ward World" ]
    assert_equal "Ward World", value["my_signups"].last["on_behalf_of"]["name"]
  end

  test "my sign-ups leave out cancelled ones and other people's" do
    assert_equal [ [ "Past Sale", "Cashier" ], [ "Bake Day", "Cashier" ], [ "Bake Day", "Cookies" ] ],
      get(:alpha_member).value["my_signups"].map { |signup| [ signup["event"]["name"], signup["position"]["name"] ] }
    assert_empty get(:alpha_manager).value["my_signups"]
  end

  test "sign-ups in a slot are capped" do
    value = get(:admin, from: "2026-03-14", limit: 1).value
    cashier = slot(value, "Bake Day", "Cashier")

    assert_equal 1, cashier["signups"].size
    assert cashier["signups_truncated"]
    assert_equal 2, cashier["filled"]
  end

  test "a slot turned off is left out for a member, as on the page" do
    @bake_day_cashier.signup_slot.update!(disabled: true)

    assert_equal [ "Cookies" ], get(:alpha_member).value["events"][1]["slots"].map { |item| item["position"]["name"] }
  end

  test "organizers also get a turned-off slot that holds sign-ups, marked disabled" do
    @bake_day_cashier.signup_slot.update!(disabled: true)
    @cleanup_slot = @cookies.signup_slots.find_by!(event: @cleanup)
    @cleanup_slot.update!(disabled: true)

    [ :admin, :alpha_manager, :organizer ].each do |viewer|
      slots = get(viewer).value["events"][1]["slots"]
      assert_equal [ [ "Cashier", true ], [ "Cookies", false ] ], slots.map { |item| [ item["position"]["name"], item["disabled"] ] }, viewer
      assert_equal [ "AlphaMember World", "Ward World" ], slots.first["signups"].map { |signup| signup["person"]["name"] }, viewer
    end
    assert_equal [ "Cashier" ], get(:admin).value["events"][2]["slots"].map { |item| item["position"]["name"] }
  end

  test "a turned-off slot's sign-ups stay off a plain member's sheet" do
    @bake_day_cashier.signup_slot.update!(disabled: true)

    assert_equal [ "Cookies" ], get(:alpha_plain).value["events"][1]["slots"].map { |item| item["position"]["name"] }
  end

  test "status is shown to organizers and those involved, not to a plain member" do
    @ward_cashier.update!(status: :fulfilled)
    plain = slot(get(:alpha_plain).value, "Bake Day", "Cashier")["signups"]
    organizer = slot(get(:alpha_manager).value, "Bake Day", "Cashier")["signups"]
    involved = slot(get(:ward).value, "Bake Day", "Cashier")["signups"]

    assert plain.none? { |signup| signup.key?("status") }
    assert_equal [ "active", "fulfilled" ], organizer.map { |signup| signup["status"] }
    assert_equal [ nil, "fulfilled" ], involved.map { |signup| signup["status"] }
  end

  test "a no-show is hidden from members and shown to organizers with its status" do
    assert_equal [ "AlphaMember World" ], holders(get(:alpha_plain).value, "Bake Day", "Cookies")
    assert_equal [ [ "AlphaMember World", "active" ], [ "Late World", "no_show" ] ],
      slot(get(:alpha_manager).value, "Bake Day", "Cookies")["signups"].map { |signup| [ signup["person"]["name"], signup["status"] ] }
  end

  test "the default sign-up limit is 25 per slot" do
    position = @sheet.signup_positions.create!(name: "Runner")
    30.times do |n|
      create_world_person("Runner#{n}", @alpha).tap { |someone| @people[:"runner#{n}"] = someone }
      create_signup(position, :"runner#{n}", @bake_day)
    end
    runner = slot(get(:alpha_plain).value, "Bake Day", "Runner")

    assert_equal [ 25, true, 30 ], [ runner["signups"].size, runner["signups_truncated"], runner["filled"] ]
  end

  test "events are capped, flagged and paged with from" do
    first = get(:alpha_member, limit: 2).value

    assert_equal [ "Past Sale", "Bake Day" ], first["events"].map { |item| item["event"]["name"] }
    assert first["events_truncated"]
    rest = get(:alpha_member, from: "2026-03-15", limit: 2).value
    assert_equal [ "Clean-up" ], rest["events"].map { |item| item["event"]["name"] }
    assert_not rest["events_truncated"]
    assert_match(/from must be a date/, get(:alpha_member, from: "March").error)
  end

  test "my sign-ups are capped and flagged" do
    value = get(:alpha_member, limit: 2).value

    assert_equal 2, value["my_signups"].size
    assert value["my_signups_truncated"]
    assert_not get(:alpha_member).value["my_signups_truncated"]
  end

  test "a wrong ID is not found" do
    assert_equal "Not found", call_tool("get_signup_sheet", user: user(:admin), sheet_id: @bake_day.neat_id).error
  end

  test "feature off means the tool is neither listed nor callable" do
    with_feature(:signups, false) do
      refute_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "get_signup_sheet"
      assert_equal "Feature off", get(:admin).error
    end
  end
end
