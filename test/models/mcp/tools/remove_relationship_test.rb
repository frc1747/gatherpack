require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemoveRelationshipTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @teammates = Relationship.create!(parent: person(:alpha_member), child: person(:ward), relationship_type: @parent_of, created_by: person(:admin))
  end

  def remove(viewer, relationship = @teammates, **options)
    call_tool("remove_relationship", user: user(viewer), relationship_id: relationship.neat_id, **options)
  end

  test "an admin removes it and gets it back marked removed" do
    result = nil
    assert_difference("Relationship.count", -1) { result = remove(:admin) }

    assert_equal [ @teammates.neat_id, true ], result.value.values_at("id", "removed")
    assert_equal "AlphaMember World", result.value.dig("parent", "name")
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Relationship", item_id: @teammates.id, event: "destroy").last.whodunnit
  end

  test "either person in it can remove it" do
    assert_difference("Relationship.count", -1) { assert_nil remove(:ward).error }

    guardian = Relationship.find_by!(parent: person(:guardian))
    assert_difference("Relationship.count", -1) { assert_nil remove(:guardian, guardian).error }
  end

  test "the team's manager sees it but can't remove it" do
    assert_refused("Not allowed", Relationship, AuditLog) { remove(:alpha_manager) }
  end

  test "someone on another team or outside it can't reach it" do
    assert_refused("Not found", Relationship, AuditLog) { remove(:beta_member) }
    assert_refused("Not found", Relationship, AuditLog) { remove(:guardian) }
  end

  test "a build's destroy? allowing someone outside the scope lets them" do
    outside = Relationship.find_by!(parent: person(:guardian))

    with_policy_query(RelationshipPolicy, :destroy?, proc { true }) do
      assert_difference("Relationship.count", -1) { assert_nil remove(:beta_member, outside).error }
    end
  end

  test "a read token, the setting being off and a bad ID refuse it" do
    assert_refused("Not allowed", Relationship) { remove(:admin, scopes: "mcp_read") }
    assert_refused("Writes disabled", Relationship) { remove(:admin, writes_enabled: false) }
    assert_refused("Not found", Relationship) { call_tool("remove_relationship", user: user(:admin), relationship_id: @teammates.id) }
  end

  test "it runs the relationship's hooks" do
    assert_hook_runs("relationships - destroy") { remove(:admin) }
  end

  test "it allows and refuses as the page does" do
    %i[admin ward alpha_member alpha_manager beta_member guardian].each do |viewer|
      page = page_changes_rows?(Relationship, as: user(viewer)) { delete person_relationship_path(person(:ward), @teammates) }
      tool = changes_rows?(Relationship) { remove(viewer) }

      assert_equal page, tool, viewer.to_s
    end
  end
end
