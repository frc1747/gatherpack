require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetTeamTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def show_team(viewer, team)
    call_tool("get_team", user: user(viewer), team_id: team.neat_id)
  end

  def member_names(result)
    result.value["members"].map { |member| member["name"].split.first }
  end

  test "an admin sees the team, its managers, members and sub-teams" do
    child = create_world_team("Alpha Child", parent: @alpha)
    @alpha.update!(description: "The A team")
    value = show_team(:admin, @alpha).value

    assert_equal [ @alpha.neat_id, "Alpha", "The A team", team_types(:one).name, nil ], value.values_at("id", "name", "description", "team_type", "parent")
    assert_equal [ { "id" => child.neat_id, "name" => "Alpha Child" } ], value["children"]
    assert_equal [ { "id" => person(:alpha_manager).neat_id, "name" => "AlphaManager World" } ], value["managers"]
    assert_equal [ [ "AlphaManager", true ], [ "AlphaMember", false ], [ "Ward", false ] ],
      value["members"].map { |member| [ member["name"].split.first, member["manager"] ] }
  end

  test "membership IDs go only to viewers who may remove the membership" do
    ids = ->(viewer) { show_team(viewer, @alpha).value["members"].map { |member| member["membership_id"] } }
    all = @alpha.memberships.joins(:person).order("people.last_name", "people.first_name", "memberships.id").map(&:neat_id)

    assert_equal all, ids.call(:admin)
    assert_equal all, ids.call(:alpha_manager)
    assert_equal [ nil, nil, nil ], ids.call(:alpha_member)
    assert_equal [ nil, nil, nil ], ids.call(:ward)
  end

  test "a membership ID is there exactly when remove_team_member accepts it" do
    target = Membership.find_by!(person: person(:ward), team: @alpha)
    @alpha.update!(join_permission: :has_account)

    %i[admin alpha_manager alpha_member ward beta_member guardian].each do |viewer|
      listed = show_team(viewer, @alpha).value["members"].find { |member| member["id"] == person(:ward).neat_id }
      removed = changes_rows?(Membership) { call_tool("remove_team_member", user: user(viewer), membership_id: target.neat_id) }

      assert_equal removed, listed&.dig("membership_id") == target.neat_id, viewer
    end
  end

  test "a sub-team shows its parent" do
    child = create_world_team("Alpha Child", parent: @alpha)

    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, show_team(:admin, child).value["parent"])
  end

  test "a manager sees their team" do
    assert_equal %w[AlphaManager AlphaMember Ward], member_names(show_team(:alpha_manager, @alpha))
  end

  test "a member sees their own team and not a team limited to admins" do
    assert_equal %w[AlphaManager AlphaMember Ward], member_names(show_team(:alpha_member, @alpha))
    assert_equal "Not found", show_team(:alpha_member, @beta).error
  end

  test "a guardian in no team can't find a team that isn't open" do
    assert_equal "Not found", show_team(:guardian, @alpha).error
  end

  test "an open team shows its description and managers but only the members the viewer can see" do
    @beta.update!(join_permission: :has_account, description: "Open to all")
    @beta.memberships.find_by!(person: person(:beta_member)).update!(manager: true)
    value = show_team(:alpha_member, @beta).value

    assert_equal "Open to all", value["description"]
    assert_equal [ "BetaMember World" ], value["managers"].map { |manager| manager["name"] }
    assert_empty value["members"]
  end

  test "the member list follows the team page: full only with show_full?" do
    root = create_world_team("Root")
    @alpha.update!(parent: root, join_permission: :has_account)
    Membership.create!(person: person(:beta_member), team: root, manager: true)
    everyone = %w[AlphaManager AlphaMember Ward]

    assert_equal everyone, member_names(show_team(:admin, @alpha))
    assert_equal everyone, member_names(show_team(:alpha_manager, @alpha))
    assert_equal everyone, member_names(show_team(:beta_member, @alpha)), "manager of a parent team"
    assert_equal everyone, member_names(show_team(:alpha_member, @alpha))
    assert_equal everyone, member_names(show_team(:ward, @alpha))
    assert_empty member_names(show_team(:badge_holder, @alpha)), "member of a different team"
    assert_empty member_names(show_team(:guardian, @alpha)), "a viewer in no team"
  end

  test "a viewer with a person in common with an open team isn't shown that person" do
    @alpha.update!(join_permission: :has_account)
    Membership.create!(person: person(:badge_holder), team: @alpha)

    assert_includes member_names(show_team(:admin, @alpha)), "BadgeHolder"
    assert_empty member_names(show_team(:beta_member, @alpha))
  end

  test "a viewer without show_full? still sees the managers and no members" do
    @alpha.update!(join_permission: :has_account)
    Membership.find_by!(person: person(:alpha_member), team: @alpha).update!(manager: true)
    value = show_team(:guardian, @alpha).value

    assert_equal [ "AlphaManager World", "AlphaMember World" ], value["managers"].map { |manager| manager["name"] }
    assert_empty value["members"]
  end

  test "the full member list goes exactly to those the team page renders in full" do
    @alpha.update!(join_permission: :has_account)
    Membership.create!(person: person(:badge_holder), team: @alpha)

    %i[admin alpha_manager alpha_member ward beta_member badge_holder guardian].each do |viewer|
      sign_in user(viewer)
      get team_path(@alpha)
      full_page = response.body.include?("About Alpha")
      sign_out user(viewer)

      assert_response :success
      assert_equal full_page, member_names(show_team(viewer, @alpha)).any?, viewer
    end
  end

  test "sub-teams the viewer can't see are left out" do
    create_world_team("Hidden Child", parent: @alpha)
    create_world_team("Open Child", parent: @alpha).update!(join_permission: :has_account)

    assert_equal [ "Hidden Child", "Open Child" ], show_team(:alpha_manager, @alpha).value["children"].map { |child| child["name"] }
    assert_equal [ "Open Child" ], show_team(:alpha_member, @alpha).value["children"].map { |child| child["name"] }
  end

  test "members are limited, ordered, and flagged when truncated" do
    30.times { |i| Membership.create!(person: Person.create!(first_name: "Extra#{i}", last_name: "Zed"), team: @alpha) }
    value = show_team(:admin, @alpha).value

    assert_equal 25, value["members"].size
    assert_equal true, value["truncated"]
    assert_equal value["members"], show_team(:admin, @alpha).value["members"]
    assert_equal 33, call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id, limit: 100).value["members"].size
    assert_equal false, call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id, limit: 100).value["truncated"]
    assert_equal 2, call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id, limit: 2).value["members"].size
  end

  test "a parent the viewer can't see is null" do
    hidden = create_world_team("SecretParent")
    open_child = create_world_team("Open Child", parent: hidden)
    open_child.update!(join_permission: :has_account)

    assert_nil show_team(:beta_member, open_child).value["parent"]
    assert_equal "SecretParent", show_team(:admin, open_child).value.dig("parent", "name")
  end

  test "a wrong ID prefix is not found" do
    assert_equal "Not found", call_tool("get_team", user: user(:admin), team_id: person(:admin).neat_id).error
  end
end
