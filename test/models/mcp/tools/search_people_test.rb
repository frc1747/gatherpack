require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::SearchPeopleTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def names(result)
    result.value["items"].map { |item| item["name"].split.first }
  end

  test "an admin finds anyone" do
    assert_equal %w[Admin AlphaManager AlphaMember BadgeHolder BetaMember Guardian Ward],
      names(call_tool("search_people", user: user(:admin), query: "World")).sort
  end

  test "matching is case-insensitive and partial" do
    assert_equal [ "BetaMember" ], names(call_tool("search_people", user: user(:admin), query: "betam"))
  end

  test "a manager finds their team and themselves, not another team" do
    assert_equal %w[AlphaManager AlphaMember Ward], names(call_tool("search_people", user: user(:alpha_manager), query: "World")).sort
  end

  test "a member on another team sees only their own team" do
    found = names(call_tool("search_people", user: user(:beta_member), query: "World")).sort

    assert_equal %w[BadgeHolder BetaMember], found
  end

  test "a guardian in no team finds only themselves, as on the people index" do
    assert_equal [ "Guardian" ], names(call_tool("search_people", user: user(:guardian), query: "World"))
  end

  test "people come in the compact shape with their teams and no contact details" do
    item = call_tool("search_people", user: user(:admin), query: "BetaMember").value["items"].first

    assert_equal({ "id" => person(:beta_member).neat_id, "name" => "BetaMember World",
      "teams" => [ { "id" => @beta.neat_id, "name" => "Beta" } ] }, item)
  end

  test "only the name is matched, so contact details can't confirm who someone is" do
    # One is a minor, one an adult: finding either by these would say whose they are.
    { ward: 16.years.ago.to_date, alpha_member: Date.new(1990, 5, 6) }.each do |target, birthday|
      person(target).update!(phone_number: "555-0100", address: "1 Main St", birthday: birthday)

      [ "555-0100", "1 Main St", user(target).email, birthday.iso8601 ].each do |query|
        assert_empty call_tool("search_people", user: user(:admin), query: query).value["items"], query
      end
    end
  end

  test "teams the viewer can't see are left out" do
    @beta.update!(join_permission: :added_by_admin)
    Membership.create!(person: person(:alpha_member), team: @beta)
    item = call_tool("search_people", user: user(:alpha_manager), query: "AlphaMember").value["items"].first

    assert_equal [ @alpha.neat_id ], item["teams"].map { |team| team["id"] }
  end

  test "team filter matches direct members" do
    result = call_tool("search_people", user: user(:admin), query: "World", team_id: @beta.neat_id)

    assert_equal %w[BadgeHolder BetaMember], names(result).sort
  end

  test "a team outside the viewer's scope is not found" do
    @beta.update!(join_permission: :added_by_admin)
    result = call_tool("search_people", user: user(:alpha_member), query: "World", team_id: @beta.neat_id)

    assert_equal "Not found", result.error
  end

  test "a visible open team doesn't reveal members the viewer can't see" do
    @beta.update!(join_permission: :has_account)
    result = call_tool("search_people", user: user(:alpha_member), query: "World", team_id: @beta.neat_id)

    assert_empty result.value["items"]
  end

  test "team filter on an open team lists the roster only where the team page shows it" do
    root = create_world_team("Root")
    @alpha.update!(parent: root, join_permission: :has_account)
    Membership.create!(person: person(:beta_member), team: root, manager: true)
    search = ->(viewer) { names(call_tool("search_people", user: user(viewer), query: "World", team_id: @alpha.neat_id)).sort }
    everyone = %w[AlphaManager AlphaMember Ward]

    assert_equal everyone, search.call(:admin)
    assert_equal everyone, search.call(:alpha_manager)
    assert_equal everyone, search.call(:beta_member), "manager of a parent team"
    assert_equal everyone, search.call(:alpha_member)
    assert_equal everyone, search.call(:ward)
    assert_empty search.call(:badge_holder), "member of a different team"
    assert_empty search.call(:guardian), "a viewer in no team"
  end

  test "team filter on an open team doesn't list a person the viewer has in common with it" do
    @alpha.update!(join_permission: :has_account)
    Membership.create!(person: person(:badge_holder), team: @alpha)
    search = ->(viewer) { names(call_tool("search_people", user: user(viewer), query: "World", team_id: @alpha.neat_id)) }

    assert_includes search.call(:admin), "BadgeHolder"
    assert_empty search.call(:beta_member)
  end

  test "a wrong ID prefix is not found" do
    result = call_tool("search_people", user: user(:admin), query: "World", team_id: person(:admin).neat_id)

    assert_equal "Not found", result.error
  end

  test "badge filter matches holders within the viewer's scope" do
    assert_equal [ "BadgeHolder" ], names(call_tool("search_people", user: user(:admin), query: "World", badge_id: @access_badge.neat_id))
    assert_empty names(call_tool("search_people", user: user(:alpha_member), query: "World", badge_id: @access_badge.neat_id))
  end

  test "a team badge the viewer can't see is not found" do
    badge = create_world_badge("Beta Badge", team: @beta)
    result = call_tool("search_people", user: user(:alpha_member), query: "World", badge_id: badge.neat_id)

    assert_equal "Not found", result.error
  end

  test "badge filter refuses when badges are off" do
    with_feature(:badges, false) do
      assert_equal "Badges are off", call_tool("search_people", user: user(:admin), query: "World", badge_id: @access_badge.neat_id).error
    end
  end

  test "limit truncates, in a deterministic order" do
    result = call_tool("search_people", user: user(:admin), query: "World", limit: 2)

    assert_equal 2, result.value["items"].size
    assert_equal true, result.value["truncated"]
    assert_equal result.value, call_tool("search_people", user: user(:admin), query: "World", limit: 2).value
    assert_equal false, call_tool("search_people", user: user(:admin), query: "World", limit: 100).value["truncated"]
  end

  test "a limit over the cap is an invalid argument" do
    assert_match(/Invalid arguments/, call_tool("search_people", user: user(:admin), query: "World", limit: 101).error)
  end

  test "a blank query is an invalid argument" do
    assert_equal "query can't be blank", call_tool("search_people", user: user(:admin), query: "  ").error
  end
end
