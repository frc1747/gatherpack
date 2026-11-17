require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListMembershipApplicationsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    @alpha.update!(join_permission: :requires_approval)
    @beta.update!(join_permission: :requires_approval)
    @application = MembershipApplication.create!(person: person(:guardian), team: @alpha, message: "Please")
    @other = MembershipApplication.create!(person: person(:alpha_member), team: @beta)
  end

  def ids(viewer, **options)
    call_tool("list_membership_applications", user: user(viewer), **options).value["items"].map { |item| item["id"] }
  end

  test "an admin sees every pending one, with who, where and the message" do
    assert_equal [ @application, @other ].map(&:neat_id).sort, ids(:admin).sort

    item = call_tool("list_membership_applications", user: user(:admin), team_id: @alpha.neat_id).value["items"].sole
    assert_equal [ "Guardian World", "Alpha", "pending", "Please" ], [ item.dig("person", "name"), item.dig("team", "name"), item["status"], item["message"] ]
  end

  test "a team manager sees their team's and their own" do
    assert_equal [ @application.neat_id ], ids(:alpha_manager)
  end

  test "a plain member sees only their own, and a guardian theirs" do
    assert_equal [ @other.neat_id ], ids(:alpha_member)
    assert_empty ids(:ward)
    assert_empty ids(:beta_member)
    assert_equal [ @application.neat_id ], ids(:guardian)
  end

  test "decided ones are left out" do
    @application.deny!
    assert_equal [ @other.neat_id ], ids(:admin)
  end

  test "the team filter narrows the list, and a team nobody can see is not found" do
    assert_equal [ @other.neat_id ], ids(:admin, team_id: @beta.neat_id)
    assert_empty ids(:alpha_manager, team_id: @beta.neat_id)

    @beta.update_columns(join_permission: Team.join_permissions[:added_by_admin])
    assert_equal "Not found", call_tool("list_membership_applications", user: user(:ward), team_id: @beta.neat_id).error
  end

  test "it's limited" do
    result = call_tool("list_membership_applications", user: user(:admin), limit: 1)
    assert_equal [ 1, true ], [ result.value["items"].size, result.value["truncated"] ]
  end
end
