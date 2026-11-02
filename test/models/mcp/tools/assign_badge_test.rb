require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::AssignBadgeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @alpha_badge = create_world_badge_with(:added_by_manager, team: @alpha)
    @beta_badge = create_world_badge_with(:added_by_manager, team: @beta)
  end

  def assign(viewer, holder, badge, **options)
    call_tool("assign_badge", user: user(viewer), person_id: person(holder).neat_id, badge_id: badge.neat_id, **options)
  end

  test "an admin gives any person a badge and gets the assignment back" do
    result = assign(:admin, :beta_member, @access_badge)

    assignment = BadgeAssignment.find_by!(person: person(:beta_member), badge: @access_badge)
    assert_equal assignment, result.changed
    assert_equal assignment.neat_id, result.value["id"]
    assert_equal person(:beta_member).neat_id, result.value.dig("person", "id")
    assert_equal @access_badge.neat_id, result.value.dig("badge", "id")
  end

  test "a team manager gives their team's badge to a member, or themselves" do
    assert_difference("BadgeAssignment.count", 2) do
      assert_nil assign(:alpha_manager, :alpha_member, @alpha_badge).error
      assert_nil assign(:alpha_manager, :alpha_manager, @alpha_badge).error
    end
  end

  test "a team manager can't give an admin-only badge, even to themselves" do
    assert_refused("Not allowed", BadgeAssignment) { assign(:alpha_manager, :alpha_member, @access_badge) }
    assert_refused("Not allowed", BadgeAssignment) { assign(:alpha_manager, :alpha_manager, @access_badge) }
  end

  test "a plain member on another team can't reach the badge or the person" do
    assert_refused("Not found", BadgeAssignment) { assign(:beta_member, :beta_member, @alpha_badge) }
    assert_refused("Not found", BadgeAssignment) { assign(:beta_member, :alpha_member, @access_badge) }
  end

  test "a plain member can't grant themselves a manager or admin badge" do
    assert_refused("Not allowed", BadgeAssignment) { assign(:beta_member, :beta_member, @beta_badge) }
    assert_refused("Not allowed", BadgeAssignment) { assign(:beta_member, :beta_member, @access_badge) }
  end

  test "a current member gives a current-member badge to a teammate" do
    badge = create_world_badge_with(:added_by_current_member, team: @alpha)

    assert_nil assign(:alpha_member, :ward, badge).error
  end

  SELF_SERVICE = %i[added_by_admin_or_self added_by_manager_or_self has_account].freeze

  test "on a self-service badge, a plain member chooses only themselves" do
    SELF_SERVICE.each do |permission|
      badge = create_world_badge_with(permission)
      team_badge = create_world_badge_with(permission, team: @beta)

      assert_nil assign(:beta_member, :beta_member, badge).error, permission
      assert_nil assign(:beta_member, :beta_member, team_badge).error, permission
      assert_refused("Not allowed", BadgeAssignment) { assign(:beta_member, :badge_holder, badge) }
      assert_refused("Not allowed", BadgeAssignment) { assign(:beta_member, :badge_holder, team_badge) }
      assert_refused("Not found", BadgeAssignment) { assign(:beta_member, :alpha_member, badge) }
    end
  end

  test "on a self-service badge, a manager chooses themselves or people they manage" do
    parent = create_world_team("Parent")
    kid = create_world_team("Kid", parent: parent)
    sibling = create_world_team("Sibling", parent: parent)
    kid_manager = create_world_person("KidManager", kid, manager: true)
    kid_member = create_world_person("KidMember", kid)
    sibling_member = create_world_person("SiblingMember", sibling)
    @people.merge!(kid_manager: kid_manager, kid_member: kid_member, sibling_member: sibling_member)

    SELF_SERVICE.each do |permission|
      badge = create_world_badge_with(permission)

      assert_nil assign(:kid_manager, :kid_manager, badge).error, permission
      assert_nil assign(:kid_manager, :kid_member, badge).error, permission
      assert_refused("Not allowed", BadgeAssignment) { assign(:kid_manager, :sibling_member, badge) }
    end
  end

  test "on a self-service badge, an admin chooses anyone" do
    SELF_SERVICE.each { |permission| assert_nil assign(:admin, :beta_member, create_world_badge_with(permission)).error, permission }
  end

  test "a guardian can't reach their ward, and is held to the badge's permission for themselves" do
    open_badge = create_world_badge_with(:has_account)

    assert_refused("Not found", BadgeAssignment) { assign(:guardian, :ward, open_badge) }
    assert_refused("Not found", BadgeAssignment) { assign(:guardian, :guardian, @alpha_badge) }
    assert_refused("Not allowed", BadgeAssignment) { assign(:guardian, :guardian, @access_badge) }
    assert_nil assign(:guardian, :guardian, open_badge).error
  end

  test "a team badge needs the person on the team" do
    assert_refused(/must be a member of the badge's team/, BadgeAssignment) { assign(:admin, :beta_member, @alpha_badge) }
    assert_equal "error", McpToolCall.order(:created_at).last.outcome
  end

  test "a duplicate returns the validation message" do
    assert_refused("Person already has this badge", BadgeAssignment) { assign(:admin, :badge_holder, @access_badge) }
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "per_nonsense", "bdg_", @beta.neat_id ].each do |bad|
      assert_refused("Not found", BadgeAssignment) { call_tool("assign_badge", user: user(:admin), person_id: bad, badge_id: @access_badge.neat_id) }
      assert_refused("Not found", BadgeAssignment) { call_tool("assign_badge", user: user(:admin), person_id: person(:ward).neat_id, badge_id: bad) }
    end
    assert_refused(/badge_id/, BadgeAssignment) { call_tool("assign_badge", user: user(:admin), person_id: person(:ward).neat_id) }
    assert_refused(/.+/, BadgeAssignment) { call_tool("assign_badge", user: user(:admin), person_id: 7, badge_id: @access_badge.neat_id) }
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_refused("Not allowed", BadgeAssignment) { assign(:admin, :ward, @access_badge, scopes: "mcp_read") }
    assert_refused("Writes disabled", BadgeAssignment) { assign(:admin, :ward, @access_badge, writes_enabled: false) }
    with_feature(:badges, false) { assert_refused("Feature off", BadgeAssignment) { assign(:admin, :ward, @access_badge) } }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("badge_assignments - create") { assign(:admin, :ward, @access_badge) }
  end

  test "it allows and refuses as the page does" do
    open_badge = create_world_badge_with(:has_account)
    [
      [ :admin, :beta_member, @access_badge ],
      [ :admin, :beta_member, @alpha_badge ],
      [ :alpha_manager, :alpha_member, @alpha_badge ],
      [ :alpha_manager, :alpha_member, @access_badge ],
      [ :alpha_manager, :alpha_member, @beta_badge ],
      [ :alpha_member, :alpha_member, @alpha_badge ],
      [ :alpha_manager, :ward, open_badge ],
      [ :beta_member, :beta_member, @beta_badge ],
      [ :beta_member, :beta_member, @alpha_badge ],
      [ :guardian, :guardian, @access_badge ],
      [ :guardian, :guardian, open_badge ],
      [ :guardian, :ward, @access_badge ]
    ].each do |viewer, holder, badge|
      page = page_changes_rows?(BadgeAssignment, as: user(viewer)) do
        post badge_badge_assignments_path(badge), params: { badge_assignment: { person_id: person(holder).id } }
      end
      tool = changes_rows?(BadgeAssignment) { assign(viewer, holder, badge) }

      assert_equal page, tool, "#{viewer} giving #{holder} #{badge.name}"
    end
  end

  # The POST passes everyone on a self-service badge, whoever they choose.
  test "it refuses a self-service grant to a teammate the viewer doesn't manage, where the POST goes through" do
    open_badge = create_world_badge_with(:has_account)
    page = page_changes_rows?(BadgeAssignment, as: user(:alpha_member)) do
      post badge_badge_assignments_path(open_badge), params: { badge_assignment: { person_id: person(:ward).id } }
    end

    assert page
    assert_refused("Not allowed", BadgeAssignment) { assign(:alpha_member, :ward, open_badge) }
  end

  # The POST doesn't check the person, though its form only offers people in scope.
  test "it refuses a person the viewer can't see, where a hand-made POST goes through" do
    open_badge = create_world_badge_with(:has_account)
    page = page_changes_rows?(BadgeAssignment, as: user(:guardian)) do
      post badge_badge_assignments_path(open_badge), params: { badge_assignment: { person_id: person(:ward).id } }
    end

    assert page
    assert_refused("Not found", BadgeAssignment) { assign(:guardian, :ward, open_badge) }
  end
end
