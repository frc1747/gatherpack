require "test_helper"

# Runs only where feature/person-merge is present (an integration build).
class McpPersonMergeTest < ActiveSupport::TestCase
  setup { skip "needs feature/person-merge" unless defined?(GatherPack::PersonMerge) }

  test "covers the login and the changed record of a tool call" do
    assert GatherPack::PersonMerge.covers?(:mcp_tool_calls, :user_id, owner: :user)
    %i[ person user ].each do |owner|
      assert GatherPack::PersonMerge.covers?(:mcp_tool_calls, :changed_id, owner: owner), "mcp_tool_calls.changed_id (#{owner})"
    end
  end

  test "changed records are matched by the model name the call log stores" do
    entry = GatherPack::PersonMerge.entries(:person).find { |e| e.table == "mcp_tool_calls" }

    assert_equal "changed_type", entry.type_column
    assert_equal Person.name, GatherPack::PersonMerge::OWNER_TYPES.fetch(:person)
    assert_equal User.name, GatherPack::PersonMerge::OWNER_TYPES.fetch(:user)
  end
end
