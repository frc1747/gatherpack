require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemoveBadgeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @alpha_badge = create_world_badge_with(:added_by_manager, team: @alpha)
    @alpha_assignment = BadgeAssignment.create!(badge: @alpha_badge, person: person(:alpha_member))
    @holder_assignment = BadgeAssignment.find_by!(badge: @access_badge, person: person(:badge_holder))
  end

  def ctx_allows_destroy?(viewer, assignment)
    mcp_context(user(viewer), scopes: "mcp_write").allowed?(assignment, :destroy?)
  end

  def remove(viewer, assignment, **options)
    call_tool("remove_badge", user: user(viewer), badge_assignment_id: assignment.neat_id, **options)
  end

  test "it is marked destructive" do
    assert Mcp.tool("remove_badge").annotations[:destructive_hint]
  end

  test "an admin removes any assignment and gets it back" do
    result = remove(:admin, @holder_assignment)

    assert_not BadgeAssignment.exists?(@holder_assignment.id)
    assert_equal @holder_assignment, result.changed
    assert_equal [ @holder_assignment.neat_id, true ], result.value.values_at("id", "removed")
    assert_equal person(:badge_holder).neat_id, result.value.dig("person", "id")
    assert_equal @access_badge.neat_id, result.value.dig("badge", "id")
  end

  test "a team manager removes their team's badge" do
    assert_difference("BadgeAssignment.count", -1) { assert_nil remove(:alpha_manager, @alpha_assignment).error }
  end

  test "a team manager can't remove an admin-only badge they can see" do
    assignment = BadgeAssignment.create!(badge: @access_badge, person: person(:alpha_member))

    assert_refused("Not allowed", BadgeAssignment) { remove(:alpha_manager, assignment) }
  end

  test "a holder can't remove their own badge when its permission doesn't let them" do
    assert_refused("Not allowed", BadgeAssignment) { remove(:badge_holder, @holder_assignment) }
    assert_refused("Not allowed", BadgeAssignment) { remove(:alpha_member, @alpha_assignment) }
  end

  test "a plain member on another team can't reach the badge or the holder" do
    assert_refused("Not found", BadgeAssignment) { remove(:beta_member, @alpha_assignment) }

    assignment = BadgeAssignment.create!(badge: create_world_badge_with(:has_account), person: person(:alpha_member))
    assert_refused("Not found", BadgeAssignment) { remove(:beta_member, assignment) }
  end

  # destroy? passes for the holder's own assignment, and they have left the
  # badge's team: only the gate on the badge stops this.
  test "a holder who no longer sees the badge can't reach the assignment" do
    @people[:both] = create_world_person("Both", @alpha)
    Membership.create!(person: person(:both), team: @beta)
    badge = create_world_badge_with(:has_account, team: @alpha)
    assignment = BadgeAssignment.create!(badge: badge, person: person(:both))
    Membership.find_by!(person: person(:both), team: @alpha).destroy!

    assert ctx_allows_destroy?(:both, assignment)
    assert_refused("Not found", BadgeAssignment) { remove(:both, assignment) }
    assert BadgeAssignment.exists?(assignment.id)
    assert_not page_changes_rows?(BadgeAssignment, as: user(:both)) { delete badge_badge_assignment_path(badge, assignment) }
  end

  test "a viewer who sees the holder but not the badge can't reach the assignment, and destroy? refuses too" do
    both = create_world_person("Both", @alpha)
    Membership.create!(person: both, team: @beta)
    badge = create_world_badge_with(:has_account, team: @alpha)
    assignment = BadgeAssignment.create!(badge: badge, person: both)

    assert_not ctx_allows_destroy?(:beta_member, assignment)
    assert_refused("Not found", BadgeAssignment) { remove(:beta_member, assignment) }
    assert BadgeAssignment.exists?(assignment.id)
    assert_not page_changes_rows?(BadgeAssignment, as: user(:beta_member)) { delete badge_badge_assignment_path(badge, assignment) }
  end

  test "a guardian can't reach their ward's badge" do
    assignment = BadgeAssignment.create!(badge: create_world_badge_with(:has_account), person: person(:ward))

    assert_refused("Not found", BadgeAssignment) { remove(:guardian, assignment) }
  end

  SELF_SERVICE = %i[added_by_admin_or_self added_by_manager_or_self has_account].freeze

  test "on a self-service badge, a plain member removes only their own" do
    SELF_SERVICE.each do |permission|
      badge = create_world_badge_with(permission)
      own = BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
      teammate = BadgeAssignment.create!(badge: badge, person: person(:ward))
      manager = BadgeAssignment.create!(badge: badge, person: person(:alpha_manager))

      assert_refused("Not allowed", BadgeAssignment) { remove(:alpha_member, teammate) }
      assert_refused("Not allowed", BadgeAssignment) { remove(:alpha_member, manager) }
      assert_nil remove(:alpha_member, own).error, permission
    end
  end

  # Stricter than the tool's own rule: this build's policy lets a manager choose
  # others only on a team-less "added by manager or self" badge.
  test "on a self-service badge, a manager removes their own, and that of people they manage where the badge lets them, not others they can see" do
    parent = create_world_team("Parent")
    kid = create_world_team("Kid", parent: parent)
    sibling = create_world_team("Sibling", parent: parent)
    @people[:kid_manager] = create_world_person("KidManager", kid, manager: true)
    @people[:kid_member] = create_world_person("KidMember", kid)
    @people[:sibling_member] = create_world_person("SiblingMember", sibling)

    SELF_SERVICE.each do |permission|
      badge = create_world_badge_with(permission)
      own = BadgeAssignment.create!(badge: badge, person: person(:kid_manager))
      managed = BadgeAssignment.create!(badge: badge, person: person(:kid_member))
      other = BadgeAssignment.create!(badge: badge, person: person(:sibling_member))

      assert_refused("Not allowed", BadgeAssignment) { remove(:kid_manager, other) }
      if permission == :added_by_manager_or_self
        assert_nil remove(:kid_manager, managed).error, permission
      else
        assert_refused("Not allowed", BadgeAssignment) { remove(:kid_manager, managed) }
      end
      assert_nil remove(:kid_manager, own).error, permission
    end
  end

  test "on a self-service badge, an admin removes anyone's" do
    SELF_SERVICE.each do |permission|
      assignment = BadgeAssignment.create!(badge: create_world_badge_with(permission), person: person(:beta_member))

      assert_nil remove(:admin, assignment).error, permission
    end
  end

  # The team's manager doesn't manage an admin who joined the team, so the
  # self-service rule would refuse this; a member still removes only their own.
  test "a badge that isn't self-service isn't held to the self-service rule" do
    badge = create_world_badge_with(:added_by_current_member, team: @alpha)
    Membership.create!(person: person(:admin), team: @alpha)
    held_by_admin = BadgeAssignment.create!(badge: badge, person: person(:admin))
    own = BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    teammate = BadgeAssignment.create!(badge: badge, person: person(:ward))

    assert_nil remove(:alpha_manager, held_by_admin).error
    assert_refused("Not allowed", BadgeAssignment) { remove(:alpha_member, teammate) }
    assert_nil remove(:alpha_member, own).error
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "bda_nonsense", @access_badge.neat_id ].each do |bad|
      assert_refused("Not found", BadgeAssignment) { call_tool("remove_badge", user: user(:admin), badge_assignment_id: bad) }
    end
    assert_refused(/badge_assignment_id/, BadgeAssignment) { call_tool("remove_badge", user: user(:admin)) }
  end

  test "a second removal is not found" do
    remove(:admin, @holder_assignment)

    assert_refused("Not found", BadgeAssignment) { remove(:admin, @holder_assignment) }
  end

  test "a read token and the setting being off refuse it, and so does the feature" do
    assert_refused("Not allowed", BadgeAssignment) { remove(:admin, @holder_assignment, scopes: "mcp_read") }
    assert_refused("Writes disabled", BadgeAssignment) { remove(:admin, @holder_assignment, writes_enabled: false) }
    with_feature(:badges, false) { assert_refused("Feature off", BadgeAssignment) { remove(:admin, @holder_assignment) } }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("badge_assignments - destroy") { remove(:admin, @holder_assignment) }
  end

  test "it allows and refuses as the page does" do
    in_alpha = BadgeAssignment.create!(badge: @access_badge, person: person(:alpha_member))
    open_in_alpha = BadgeAssignment.create!(badge: create_world_badge_with(:has_account), person: person(:ward))
    [
      [ :admin, @holder_assignment ],
      [ :admin, @alpha_assignment ],
      [ :alpha_manager, @alpha_assignment ],
      [ :alpha_manager, in_alpha ],
      [ :alpha_member, @alpha_assignment ],
      [ :alpha_manager, open_in_alpha ],
      [ :badge_holder, @holder_assignment ],
      [ :beta_member, @alpha_assignment ],
      [ :guardian, @alpha_assignment ]
    ].each do |viewer, assignment|
      page = page_changes_rows?(BadgeAssignment, as: user(viewer)) do
        delete badge_badge_assignment_path(assignment.badge, assignment)
      end
      tool = changes_rows?(BadgeAssignment) { remove(viewer, assignment) }

      assert_equal page, tool, "#{viewer} removing #{assignment.identifier_name}"
    end
  end

  # This build's page checks whose badge it is, as the tool does.
  test "it refuses to remove a teammate's self-service badge, and so does the page" do
    assignment = BadgeAssignment.create!(badge: create_world_badge_with(:has_account), person: person(:alpha_manager))
    page = page_changes_rows?(BadgeAssignment, as: user(:alpha_member)) do
      delete badge_badge_assignment_path(assignment.badge, assignment)
    end

    assert_not page
    assert_refused("Not allowed", BadgeAssignment) { remove(:alpha_member, assignment) }
  end

  # This build's page checks the holder too.
  test "it refuses a holder the viewer can't see, and so does the page" do
    assignment = BadgeAssignment.create!(badge: create_world_badge_with(:has_account), person: person(:ward))
    page = page_changes_rows?(BadgeAssignment, as: user(:guardian)) do
      delete badge_badge_assignment_path(assignment.badge, assignment)
    end

    assert_not page
    assert_refused("Not found", BadgeAssignment) { remove(:guardian, assignment) }
  end
end
