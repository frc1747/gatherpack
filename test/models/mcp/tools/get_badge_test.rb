require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetBadgeTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def get(viewer, badge = @access_badge, **args)
    call_tool("get_badge", user: user(viewer), badge_id: badge.neat_id, **args)
  end

  def holder_names(result)
    result.value["holders"].map { |holder| holder["name"].split.first }
  end

  test "an admin sees the badge and all its holders" do
    BadgeAssignment.create!(badge: @access_badge, person: person(:ward))
    value = get(:admin).value

    assert_equal [ @access_badge.neat_id, "MCP Access", "MCP", "#336699", badge_types(:one).name, nil, 2, false ],
      value.values_at("id", "name", "short", "color", "badge_type", "team", "holder_count", "truncated")
    assert_equal %w[BadgeHolder Ward], holder_names(get(:admin))
  end

  test "a team manager of the badge's team sees all holders" do
    badge = create_world_badge("Alpha Badge", team: @alpha)
    badge.update!(permission: :added_by_manager)
    BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    BadgeAssignment.create!(badge: badge, person: person(:ward))

    assert_equal %w[AlphaMember Ward], holder_names(get(:alpha_manager, badge))
  end

  test "a manager who can't edit the badge sees only holders within their scope" do
    BadgeAssignment.create!(badge: @access_badge, person: person(:alpha_member))

    assert_equal %w[AlphaMember], holder_names(get(:alpha_manager))
    assert_equal 1, get(:alpha_manager).value["holder_count"]
  end

  test "a member on another team sees only the holders they can see" do
    assert_equal %w[BadgeHolder], holder_names(get(:beta_member))
    assert_empty holder_names(get(:alpha_member))
  end

  test "a guardian sees no holders they can't see" do
    assert_empty holder_names(get(:guardian))
  end

  test "a badge anyone may self-assign still shows only the holders the viewer can see" do
    %i[added_by_admin_or_self added_by_manager_or_self has_account].each do |permission|
      badge = create_world_badge("Open #{permission}")
      badge.update!(permission: permission)
      BadgeAssignment.create!(badge: badge, person: person(:badge_holder))

      %i[alpha_member alpha_manager guardian].each do |viewer|
        value = get(viewer, badge).value
        assert_empty value["holders"], "#{viewer} / #{permission}"
        assert_equal 0, value["holder_count"]
      end
      assert_equal %w[BadgeHolder], holder_names(get(:admin, badge))
    end
  end

  test "badge assignment IDs go only to viewers who may remove the assignment" do
    badge = create_world_badge_with(:added_by_manager, team: @alpha)
    assignment = BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    id = ->(viewer) { get(viewer, badge).value["holders"].first["badge_assignment_id"] }

    assert_equal assignment.neat_id, id.call(:admin)
    assert_equal assignment.neat_id, id.call(:alpha_manager)
    assert_nil id.call(:alpha_member)
    assert_nil id.call(:ward)
  end

  test "on a self-service badge, a plain member gets the ID of their own assignment only" do
    badge = create_world_badge_with(:has_account)
    own = BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    BadgeAssignment.create!(badge: badge, person: person(:ward))
    manager = BadgeAssignment.create!(badge: badge, person: person(:alpha_manager))
    ids = ->(viewer) { get(viewer, badge).value["holders"].to_h { |holder| [ holder["id"], holder["badge_assignment_id"] ] } }

    assert_equal({ person(:alpha_member).neat_id => own.neat_id, person(:ward).neat_id => nil, person(:alpha_manager).neat_id => nil }, ids.call(:alpha_member))
    # In this build a team-less "has account" badge is each holder's own, a manager's too.
    assert_equal({ person(:alpha_member).neat_id => nil, person(:ward).neat_id => nil, person(:alpha_manager).neat_id => manager.neat_id }, ids.call(:alpha_manager))
  end

  test "a badge assignment ID is there exactly when remove_badge accepts it" do
    badges = [ @access_badge, create_world_badge_with(:added_by_manager, team: @alpha), create_world_badge_with(:has_account),
      create_world_badge_with(:added_by_manager_or_self), create_world_badge_with(:added_by_admin_or_self) ]

    badges.each do |badge|
      target = BadgeAssignment.find_or_create_by!(badge: badge, person: person(:alpha_member))
      %i[admin alpha_manager alpha_member ward beta_member guardian].each do |viewer|
        listed = get(viewer, badge).value&.dig("holders")&.find { |holder| holder["id"] == person(:alpha_member).neat_id }
        removed = changes_rows?(BadgeAssignment) { call_tool("remove_badge", user: user(viewer), badge_assignment_id: target.neat_id) }

        assert_equal removed, listed&.dig("badge_assignment_id") == target.neat_id, "#{viewer} on #{badge.name}"
      end
    end
  end

  test "a team badge outside the viewer's scope is not found" do
    badge = create_world_badge("Beta Badge", team: @beta)

    assert_equal "Not found", get(:alpha_member, badge).error
    assert_equal "Not found", get(:guardian, badge).error
  end

  test "a wrong ID prefix is not found" do
    assert_equal "Not found", call_tool("get_badge", user: user(:admin), badge_id: @beta.neat_id).error
  end

  test "it is off with the badges feature" do
    with_feature(:badges, false) { assert_equal "Feature off", get(:admin).error }
  end

  test "limit truncates the holders but not the count" do
    BadgeAssignment.create!(badge: @access_badge, person: person(:ward))
    value = get(:admin, limit: 1).value

    assert_equal %w[BadgeHolder], value["holders"].map { |holder| holder["name"].split.first }
    assert_equal [ 2, true ], value.values_at("holder_count", "truncated")
  end
end
