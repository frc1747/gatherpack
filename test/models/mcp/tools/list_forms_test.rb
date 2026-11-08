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

    assert_equal %w[Cross Lunch Mixed Named Private Trip], titles(result)
    assert_equal({ "assigned" => 3, "submitted" => 2 }, item(result, "Lunch")["counts"])
    assert_equal "draft", item(result, "Trip")["status"]
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, item(result, "Lunch")["team"])
  end

  test "a team manager sees their team's forms with counts, not other teams' drafts" do
    result = list(:alpha_manager)

    assert_equal %w[Cross Lunch Mixed Named Private], titles(result)
    assert_equal({ "assigned" => 3, "submitted" => 2 }, item(result, "Lunch")["counts"])
    assert item(result, "Lunch")["can_see_results"]
  end

  test "an audience member sees the form without counts or results" do
    item = item(list(:alpha_member), "Lunch")

    assert_nil item["counts"]
    assert_not item["can_see_results"]
  end

  test "counts cover only people whose responses the viewer can read" do
    manager = list(:alpha_manager)
    admin = list(:admin)

    assert_equal({ "assigned" => 3, "submitted" => 1 }, item(manager, "Cross")["counts"])
    assert_equal({ "assigned" => 6, "submitted" => 3 }, item(admin, "Cross")["counts"])
    assert_equal({ "assigned" => 0, "submitted" => 0 }, item(manager, "Named")["counts"], "a named person outside the viewer's reach")
    assert_equal({ "assigned" => 1, "submitted" => 0 }, item(manager, "Private")["counts"])
  end

  test "only responses in effect from people still asked count" do
    counts = item(list(:admin), "Mixed")["counts"]

    assert_equal({ "assigned" => 3, "submitted" => 1 }, counts)
  end

  test "counts agree with form_status for the same viewer" do
    %i[ admin alpha_manager ].each do |viewer|
      %w[Cross Named Private Mixed Lunch].each do |title|
        form = Form.find_by!(title: title)
        counts = item(list(viewer), title)["counts"]
        status = call_tool("form_status", user: user(viewer), form_id: form.neat_id).value["counts"]

        assert_equal [ status["assigned"], status["submitted"] ], [ counts["assigned"], counts["submitted"] ], "#{title} as #{viewer}"
      end
    end
  end

  test "the team shows where the index shows it, the opening time only to those who manage the form" do
    guardian = item(list(:guardian), "Lunch")
    member = item(list(:alpha_member), "Lunch")
    manager = item(list(:alpha_manager), "Lunch")
    coordinator = item(list(:coordinator), "Lunch")

    assert_nil guardian["team"]
    assert_nil guardian["opens_at"]
    assert_nil member["team"]
    assert_equal "Alpha", coordinator["team"]["name"]
    assert_nil coordinator["opens_at"]
    assert_equal "Alpha", manager["team"]["name"]
    assert_not_nil manager["opens_at"]
  end

  test "a guardian sees the form their ward is asked, without counts" do
    result = list(:guardian)

    assert_equal %w[Cross Lunch Mixed], titles(result)
    assert_nil item(result, "Lunch")["counts"]
    assert_not item(result, "Lunch")["can_see_results"]
  end

  test "a badge-granted coordinator sees the form and may see results, but no counts" do
    item = item(list(:coordinator), "Lunch")

    assert item["can_see_results"]
    assert_nil item["counts"]
  end

  test "a member of another team doesn't see a form that doesn't ask them" do
    assert_not_includes titles(list(:beta_member)), "Lunch"
    assert_equal %w[Cross Mixed Named], titles(list(:beta_member))
  end

  test "a closed form needs a response from the viewer to be listed" do
    @lunch.update!(status: :closed)

    assert_includes titles(list(:alpha_member)), "Lunch"
    assert_not_includes titles(list(:alpha_member, status: "open")), "Lunch"

    @lunch.form_responses.find_by(subject: person(:alpha_member)).destroy!
    assert_not_includes titles(list(:alpha_member)), "Lunch"
  end

  test "status filters" do
    assert_equal %w[Cross Lunch Mixed Named Private], titles(list(:admin, status: "open"))
    assert_empty list(:admin, status: "closed").value["items"]
    @lunch.update!(status: :closed)
    assert_equal %w[Lunch], titles(list(:admin, status: "closed"))
    assert_match(/status/, list(:admin, status: "draft").error)
  end

  test "limit truncates" do
    result = list(:admin, limit: 1)

    assert_equal [ "Cross" ], titles(result)
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
