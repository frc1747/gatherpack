require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListRelationshipTypesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @friend = RelationshipType.create!(parent_label: "AAA Friend", child_label: "Friend of", permission: :added_by_user)
  end

  def list(viewer, **options)
    call_tool("list_relationship_types", user: user(viewer), **options)
  end

  test "it gives the labels, permission and whether it grants guardianship" do
    item = list(:admin, limit: 100).value["items"].find { |type| type["id"] == @friend.neat_id }

    assert_equal({ "id" => @friend.neat_id, "parent_label" => "AAA Friend", "child_label" => "Friend of", "permission" => "added_by_user", "guardianship" => false }, item)
  end

  test "everyone gets the same list, as the page shows anyone signed in" do
    expected = list(:admin, limit: 100).value["items"]

    %i[alpha_manager alpha_member beta_member guardian].each { |viewer| assert_equal expected, list(viewer, limit: 100).value["items"] }

    sign_in user(:beta_member)
    get relationship_types_path
    assert_response :success
    assert_includes response.body, "AAA Friend"
  end

  test "it's ordered and limited" do
    result = list(:admin, limit: 1)

    assert_equal [ "AAA Friend" ], result.value["items"].map { |type| type["parent_label"] }.first(1)
    assert_equal RelationshipType.count > 1, result.value["truncated"]
  end
end
