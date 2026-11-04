require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::UpdateTeamMemberTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @membership = Membership.find_by!(person: person(:alpha_member), team: @alpha)
  end

  def update(viewer, manager: true, **options)
    call_tool("update_team_member", user: user(viewer), membership_id: @membership.neat_id, manager: manager, **options)
  end

  def assert_unchanged(error)
    assert_refused(error, AuditLog) { yield }
    assert_equal false, @membership.reload.manager
  end

  test "an admin sets the flag and gets the membership back, with the admin as the audit user" do
    value = update(:admin).value

    assert_equal true, @membership.reload.manager
    assert_equal({ "id" => @membership.neat_id, "person" => { "id" => person(:alpha_member).neat_id, "name" => "AlphaMember World" }, "team" => { "id" => @alpha.neat_id, "name" => "Alpha" }, "manager" => true }, value)
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Membership", item_id: @membership.id, event: "update").last.whodunnit
  end

  test "a team manager sets and clears it, and a manager of a parent team can too" do
    assert_nil update(:alpha_manager).error
    assert_nil update(:alpha_manager, manager: false).error
    assert_equal false, @membership.reload.manager

    child = create_world_team("Alpha Child", parent: @alpha)
    @membership = Membership.create!(person: person(:ward), team: child)
    assert_nil update(:alpha_manager).error
  end

  test "a plain member can see it but not change it" do
    assert_unchanged("Not allowed") { update(:ward) }
  end

  test "a member on another team and a guardian can't reach it" do
    assert_unchanged("Not found") { update(:beta_member) }
    assert_unchanged("Not found") { update(:guardian) }
  end

  test "a read token, the setting being off and a bad ID refuse it" do
    assert_unchanged("Not allowed") { update(:admin, scopes: "mcp_read") }
    assert_unchanged("Writes disabled") { update(:admin, writes_enabled: false) }
    assert_equal "Not found", call_tool("update_team_member", user: user(:admin), membership_id: @membership.id, manager: true).error
  end

  test "manager takes only a boolean" do
    [ "no", "true", 1, nil ].each do |value|
      assert_match(/manager/, update(:admin, manager: value).error)
      assert_equal false, @membership.reload.manager
    end
  end

  test "it runs the membership's hooks" do
    assert_hook_runs("memberships - update") { update(:admin) }
  end

  test "it allows and refuses as the page does" do
    [ [ :admin, true ], [ :alpha_manager, true ], [ :ward, false ], [ :beta_member, false ], [ :guardian, false ] ].each do |viewer, allowed|
      sign_in user(viewer)
      patch team_membership_path(@alpha, @membership), params: { membership: { manager: "1" } }
      sign_out user(viewer)
      assert_equal allowed, @membership.reload.manager, "#{viewer} on the page"
      @membership.update!(manager: false)

      update(viewer)
      assert_equal allowed, @membership.reload.manager, "#{viewer} with the tool"
      @membership.update!(manager: false)
    end
  end
end
