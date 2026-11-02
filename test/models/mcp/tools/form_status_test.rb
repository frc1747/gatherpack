require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"

class Mcp::Tools::FormStatusTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
  end

  def status(viewer, form = @lunch, **args)
    call_tool("form_status", user: user(viewer), form_id: form.neat_id, **args)
  end

  def names(result)
    result.value["items"].map { |entry| entry["person"]["name"] }
  end

  test "an admin sees who is asked and who has answered" do
    value = status(:admin).value

    assert_equal 3, value["counts"]["assigned"]
    assert_equal 2, value["counts"]["submitted"]
    assert_equal 2, value["counts"]["by_status"]["complete"]
    assert_equal 1, value["counts"]["by_status"]["not_started"]
    assert_equal [ "AlphaManager World", "AlphaMember World", "Ward World" ], names(status(:admin))
    answered = value["items"].find { |entry| entry["person"]["name"] == "AlphaMember World" }
    assert_equal "complete", answered["status"]
    assert_match(/\A\d{4}-\d\d-\d\dT/, answered["submitted_at"])
    assert_nil value["items"].find { |entry| entry["person"]["name"] == "AlphaManager World" }["submitted_at"]
  end

  test "a team manager sees the same" do
    assert_equal 3, status(:alpha_manager).value["items"].size
  end

  test "a badge-granted coordinator sees the people the grant covers" do
    assert_equal 3, status(:coordinator).value["items"].size
  end

  test "a person in the audience is not allowed" do
    assert_equal "Not allowed", status(:alpha_member).error
  end

  test "a guardian answering for a ward is not allowed" do
    assert_equal "Not allowed", status(:guardian).error
  end

  test "a member of another team is not allowed" do
    assert_equal "Not allowed", status(:beta_member).error
  end

  test "a draft is for its team's managers and admins" do
    assert_equal 0, status(:admin, @trip).value["counts"]["assigned"]
    assert_equal "Not allowed", status(:alpha_manager, @trip).error
  end

  test "a status filter and limit" do
    result = status(:admin, status: "not_started")

    assert_equal [ "AlphaManager World" ], names(result)
    assert_equal 3, result.value["counts"]["assigned"]

    limited = status(:admin, limit: 1)
    assert_equal 1, limited.value["items"].size
    assert limited.value["truncated"]
  end

  test "an unknown or malformed form is not found" do
    assert_equal "Not found", call_tool("form_status", user: user(:admin), form_id: person(:admin).neat_id).error
    assert_equal "Not found", call_tool("form_status", user: user(:admin), form_id: "nope").error
    assert_equal "Missing required arguments: form_id", call_tool("form_status", user: user(:admin)).error
  end

  test "with the feature off the tool is neither listed nor callable" do
    with_feature(:forms, false) do
      assert_equal "Feature off", status(:admin).error
      assert_not_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "form_status"
    end
  end
end
