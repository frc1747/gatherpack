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

  test "a manager of one team sees only the people they can read on a form that asks two" do
    value = status(:alpha_manager, @cross).value

    assert_equal [ "AlphaManager World", "AlphaMember World", "Ward World" ], names(status(:alpha_manager, @cross))
    assert_equal 3, value["counts"]["assigned"]
    assert_equal 1, value["counts"]["submitted"]
    assert_equal 6, status(:admin, @cross).value["counts"]["assigned"]
  end

  test "a person named by a rule outside the viewer's reach is not listed" do
    value = status(:alpha_manager, @named).value

    assert_empty value["items"]
    assert_equal 0, value["counts"]["assigned"]
    assert_equal 0, value["counts"]["submitted"]
    assert_equal 1, status(:admin, @named).value["counts"]["submitted"]
  end

  test "a read level of self leaves a manager only their own row" do
    value = status(:alpha_manager, @private).value

    assert_equal [ "AlphaManager World" ], names(status(:alpha_manager, @private))
    assert_equal 1, value["counts"]["assigned"]
    assert_equal 0, value["counts"]["submitted"]
  end

  test "a grant limited to a team covers only that team's people" do
    value = status(:alpha_member, @cross).value

    assert_equal [ "AlphaManager World", "AlphaMember World", "Ward World" ], names(status(:alpha_member, @cross))
    assert_equal 1, value["counts"]["submitted"]
  end

  test "withdrawn, draft-only and no longer asked responses are not submitted, and the last is not assigned" do
    value = status(:admin, @mixed).value

    assert_equal 3, value["counts"]["assigned"]
    assert_equal 1, value["counts"]["submitted"]
    assert_equal({ "complete" => 1, "withdrawn" => 1, "draft" => 1, "no_longer_asked" => 1 }, value["counts"]["by_status"].reject { |_, n| n.zero? })
    assert_nil value["items"].find { |entry| entry["status"] == "withdrawn" }["submitted_at"]
  end

  test "people with the same name come in ID order" do
    twins = 2.times.map do |n|
      user = User.create!(email: "twin#{n}@example.com", password: "Password1!")
      Person.create!(user: user, first_name: "Twin", last_name: "World").tap { |twin| Membership.create!(person: twin, team: @alpha) }
    end

    result = status(:admin, status: "not_started")

    assert_equal twins.sort_by(&:id).map(&:neat_id), result.value["items"].select { |entry| entry["person"]["name"] == "Twin World" }.map { |entry| entry["person"]["id"] }
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
