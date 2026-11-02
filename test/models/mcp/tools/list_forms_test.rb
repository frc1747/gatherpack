require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"

class Mcp::Tools::ListFormsTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
  end

  def list(viewer, **args)
    call_tool("list_forms", user: user(viewer), **args)
  end

  def titles(result)
    result.value["items"].map { |item| item["title"] }
  end

  def item(result, title)
    result.value["items"].find { |entry| entry["title"] == title }
  end

  test "an admin sees every form but archived ones, with counts" do
    result = list(:admin)

    assert_equal %w[Lunch Trip], titles(result)
    assert_equal({ "assigned" => 3, "submitted" => 2 }, item(result, "Lunch")["counts"])
    assert_equal "draft", item(result, "Trip")["status"]
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, item(result, "Lunch")["team"])
  end

  test "a team manager sees their team's form with counts, not other teams' drafts" do
    result = list(:alpha_manager)

    assert_equal [ "Lunch" ], titles(result)
    assert_equal({ "assigned" => 3, "submitted" => 2 }, item(result, "Lunch")["counts"])
    assert item(result, "Lunch")["can_see_results"]
  end

  test "an audience member sees the form without counts or results" do
    item = item(list(:alpha_member), "Lunch")

    assert_nil item["counts"]
    assert_not item["can_see_results"]
  end

  test "a guardian sees the form their ward is asked, without counts" do
    result = list(:guardian)

    assert_equal [ "Lunch" ], titles(result)
    assert_nil item(result, "Lunch")["counts"]
    assert_not item(result, "Lunch")["can_see_results"]
  end

  test "a badge-granted coordinator sees the form and may see results, but no counts" do
    item = item(list(:coordinator), "Lunch")

    assert item["can_see_results"]
    assert_nil item["counts"]
  end

  test "a member of another team doesn't see the form" do
    assert_empty list(:beta_member).value["items"]
  end

  test "a closed form needs a response from the viewer to be listed" do
    @lunch.update!(status: :closed)

    assert_equal [ "Lunch" ], titles(list(:alpha_member))
    assert_empty list(:alpha_member, status: "open").value["items"]

    @lunch.form_responses.find_by(subject: person(:alpha_member)).destroy!
    assert_empty list(:alpha_member).value["items"]
  end

  test "status filters" do
    assert_equal %w[Lunch], titles(list(:admin, status: "open"))
    assert_empty list(:admin, status: "closed").value["items"]
    assert_match(/status/, list(:admin, status: "draft").error)
  end

  test "limit truncates" do
    result = list(:admin, limit: 1)

    assert_equal [ "Lunch" ], titles(result)
    assert result.value["truncated"]
  end

  test "with the feature off the tool is neither listed nor callable" do
    with_feature(:forms, false) do
      assert_equal "Feature off", list(:admin).error
      assert_not_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "list_forms"
    end
  end

  test "a token without the read scope is refused" do
    assert_equal "Not allowed", call_tool("list_forms", user: user(:admin), scopes: "profile").error
  end
end
