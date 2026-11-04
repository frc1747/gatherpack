require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::AddRelationshipTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @by_user = RelationshipType.create!(parent_label: "Friend", child_label: "Friend of", permission: :added_by_user)
    @by_manager = RelationshipType.create!(parent_label: "Mentor", child_label: "Mentee", permission: :added_by_manager)
    @by_participant = RelationshipType.create!(parent_label: "Buddy", child_label: "Buddy of", permission: :added_by_participant)
  end

  def add(viewer, parent, child, type, **options)
    call_tool("add_relationship", user: user(viewer), parent_id: person(parent).neat_id, child_id: person(child).neat_id, relationship_type_id: type.neat_id, **options)
  end

  test "an admin adds any type, and gets it back with both people" do
    result = nil
    assert_difference("Relationship.count", 1) { result = add(:admin, :alpha_member, :beta_member, @parent_of) }

    relationship = Relationship.find_by!(parent: person(:alpha_member), child: person(:beta_member))
    assert_equal relationship.neat_id, result.value["id"]
    assert_equal [ "AlphaMember World", "BetaMember World", "Parent of" ], [ result.value.dig("parent", "name"), result.value.dig("child", "name"), result.value.dig("relationship_type", "parent_label") ]
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Relationship", item_id: relationship.id, event: "create").last.whodunnit
  end

  test "a team manager adds a manager's type between people on their team, but not an admin's" do
    assert_difference("Relationship.count", 1) { assert_nil add(:alpha_manager, :alpha_member, :ward, @by_manager).error }
    assert_refused("Not allowed", Relationship, AuditLog) { add(:alpha_manager, :alpha_member, :ward, @parent_of) }
  end

  test "a plain member adds what the type lets them, and nothing else" do
    assert_difference("Relationship.count", 1) { assert_nil add(:alpha_member, :alpha_member, :ward, @by_participant).error }
    assert_refused("Not allowed", Relationship, AuditLog) { add(:alpha_member, :alpha_manager, :ward, @by_participant) }
    assert_refused("Not allowed", Relationship, AuditLog) { add(:alpha_member, :alpha_member, :ward, @by_manager) }
    assert_difference("Relationship.count", 1) { assert_nil add(:alpha_member, :alpha_manager, :ward, @by_user).error }
  end

  test "someone the viewer can't see is not found, for a member on another team and a guardian" do
    assert_refused("Not found", Relationship, AuditLog) { add(:beta_member, :beta_member, :ward, @by_user) }
    assert_refused("Not found", Relationship, AuditLog) { add(:guardian, :guardian, :alpha_member, @by_user) }
  end

  test "someone the viewer is already related to can be named, from either side, though they're out of scope" do
    assert_difference("Relationship.count", 1) { assert_nil add(:guardian, :guardian, :ward, @by_user).error }
    assert_difference("Relationship.count", 1) { assert_nil add(:ward, :guardian, :ward, @by_user).error }
    assert_refused("Not found", Relationship, AuditLog) { add(:guardian, :ward, :alpha_member, @by_user) }
    assert_refused("Not allowed", Relationship, AuditLog) { add(:guardian, :guardian, :ward, @by_manager) }
  end

  test "at least one side must be in the viewer's scope, being related to both isn't enough" do
    Relationship.create!(parent: person(:guardian), child: person(:beta_member), relationship_type: @parent_of, created_by: person(:admin))

    assert_refused("Not found", Relationship, AuditLog) { add(:guardian, :ward, :beta_member, @by_user) }
    assert_refused("Not found", Relationship, AuditLog) { add(:guardian, :beta_member, :ward, @by_user) }
    assert_difference("Relationship.count", 1) { assert_nil add(:ward, :alpha_member, :guardian, @by_user).error }
  end

  test "someone already related goes through on the page too" do
    page = page_changes_rows?(Relationship, as: user(:guardian)) do
      post person_relationships_path(person(:guardian)), params: { relationship: { start_node: "#{@by_user.id}:p", child_id: person(:ward).id } }
    end
    tool = changes_rows?(Relationship) { add(:guardian, :guardian, :ward, @by_user) }

    assert page
    assert tool
  end

  test "a build's consent rule, which reports on the relationship as a whole, is not allowed" do
    with_permission_check(proc { errors.add(:base, "Only the child or an admin can add this relationship") }) do
      assert_refused("Not allowed", Relationship, AuditLog) { add(:alpha_member, :alpha_member, :ward, @by_user) }
    end
  end

  test "a person can't be related to themselves" do
    assert_refused(/cannot be the same person/, Relationship, AuditLog) { add(:admin, :ward, :ward, @by_user) }
  end

  test "a read token, the setting being off and bad IDs refuse it" do
    assert_refused("Not allowed", Relationship) { add(:admin, :alpha_member, :ward, @by_user, scopes: "mcp_read") }
    assert_refused("Writes disabled", Relationship) { add(:admin, :alpha_member, :ward, @by_user, writes_enabled: false) }
    assert_refused("Not found", Relationship) { call_tool("add_relationship", user: user(:admin), parent_id: person(:ward).id, child_id: person(:alpha_member).neat_id, relationship_type_id: @by_user.neat_id) }
    assert_refused("Not found", Relationship) { call_tool("add_relationship", user: user(:admin), parent_id: person(:ward).neat_id, child_id: person(:alpha_member).neat_id, relationship_type_id: person(:ward).neat_id) }
  end

  test "a duplicate isn't refused, as on the page" do
    add(:admin, :alpha_member, :ward, @by_user)
    assert_difference("Relationship.count", 1) { assert_nil add(:admin, :alpha_member, :ward, @by_user).error }
  end

  test "it runs the relationship's hooks" do
    assert_hook_runs("relationships - create") { add(:admin, :alpha_member, :ward, @by_user) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, :alpha_member, :ward, @parent_of ],
      [ :alpha_manager, :alpha_member, :ward, @by_manager ],
      [ :alpha_manager, :alpha_member, :ward, @parent_of ],
      [ :alpha_member, :alpha_member, :ward, @by_participant ],
      [ :alpha_member, :alpha_member, :ward, @by_manager ],
      [ :ward, :alpha_member, :ward, @by_user ]
    ].each do |viewer, parent, child, type|
      page = page_changes_rows?(Relationship, as: user(viewer)) do
        post person_relationships_path(person(parent)), params: { relationship: { start_node: "#{type.id}:p", child_id: person(child).id } }
      end
      tool = changes_rows?(Relationship) { add(viewer, parent, child, type) }

      assert_equal page, tool, "#{viewer} adding #{type.parent_label}"
    end
  end

  private

  def with_permission_check(rule)
    original = Relationship.instance_method(:permission_check)
    Relationship.define_method(:permission_check, &rule)
    Relationship.send(:private, :permission_check)
    yield
  ensure
    Relationship.define_method(:permission_check, original)
    Relationship.send(:private, :permission_check)
  end
end
