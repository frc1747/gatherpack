require "test_helper"
require_relative "../../support/mcp_world"

class Mcp::CallsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    call_tool("whoami", user: user(:alpha_member))
    call_tool("search_people", user: user(:beta_member), query: "secretname")
  end

  test "an admin sees the log, newest first" do
    sign_in user(:admin)
    get mcp_calls_path

    assert_response :success
    assert_select "h1", "MCP Calls"
    assert_select "tbody tr", 2
    assert_select "tbody tr:first-child tt", "search_people"
    assert_includes response.body, "secretname"
    # code_editor.js empties a code element with no pre inside it.
    assert_select "tbody code", false
  end

  test "a call shows how many records it changed and links those with a page" do
    membership = Membership.find_by!(person: person(:ward), team: @alpha)
    McpToolCall.create!(user: user(:admin), tool: "several", outcome: "ok", changed_records: [
      { type: "Person", id: person(:ward).id }, { type: "Team", id: @alpha.id }, { type: "Membership", id: membership.id }
    ])
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child summary", "3 records"
    assert_select "tbody tr:first-child a[href=?]", person_path(person(:ward).id), "Person #{person(:ward).id}"
    assert_select "tbody tr:first-child a[href=?]", team_path(@alpha.id)
    assert_select "tbody tr:first-child a", 2
    assert_includes css_select("tbody tr:first-child").text, "Membership #{membership.id}"

    get person_path(person(:ward).id)
    assert_response :success
  end

  test "a single change links too, and a call from before changed_records still shows" do
    McpToolCall.create!(user: user(:admin), tool: "older", outcome: "ok", changed_type: "Person", changed_id: person(:ward).id)
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child", /1 record/
    assert_select "tbody tr:first-child a[href=?]", person_path(person(:ward).id)
    assert_select "tbody tr:nth-child(2) a", 0
  end

  test "a real create_person call shows its records" do
    call_tool("create_person", user: user(:admin), first_name: "New", last_name: "Comer", email: "new@example.com", team_id: @alpha.neat_id)
    created = Person.find_by!(first_name: "New")
    sign_in user(:admin)
    get mcp_calls_path

    assert_select "tbody tr:first-child summary", "3 records"
    assert_select "tbody tr:first-child a[href=?]", person_path(created.id)
    assert_not_includes response.body.downcase, "password"
  end

  test "an admin filters by user and tool" do
    sign_in user(:admin)

    get mcp_calls_path, params: { q: { user_id_eq: user(:alpha_member).id } }
    assert_select "tbody tr", 1
    assert_select "tbody tr tt", "whoami"

    get mcp_calls_path, params: { q: { tool_eq: "search_people" } }
    assert_select "tbody tr", 1
    assert_select "tbody tr tt", "search_people"
  end

  test "a member is refused" do
    sign_in user(:alpha_member)
    get mcp_calls_path

    assert_redirected_to root_path
    assert_equal "You are not allowed to do that", flash[:notice]
  end

  test "signed out goes to sign-in" do
    get mcp_calls_path

    assert_redirected_to new_user_session_path
  end

  test "feature off is a 404" do
    sign_in user(:admin)
    with_feature(:mcp, false) do
      get mcp_calls_path
      assert_response :not_found
    end
  end

  test "signed out with the feature off is a 404 too" do
    with_feature(:mcp, false) do
      get mcp_calls_path
      assert_response :not_found
    end
    with_feature(:oauth_provider, false) do
      get mcp_calls_path
      assert_response :not_found
    end
  end

  test "admins reach it from the sidebar, right after the audit log" do
    sign_in user(:admin)
    get setup_path

    links = css_select(".sidebar a").pluck("href")
    assert_equal links.index(audit_logs_path) + 1, links.index(mcp_calls_path)
    assert_select "a[href=?]", mcp_calls_path, 1, "only the sidebar links to it, not the setup page"
  end

  test "members don't get the sidebar link" do
    sign_in user(:alpha_member)
    get root_path

    assert_select "a[href=?]", mcp_calls_path, 0
  end

  test "the sidebar link goes away when the feature is off" do
    sign_in user(:admin)
    with_feature(:mcp, false) do
      get setup_path

      assert_select "a[href=?]", mcp_calls_path, 0
    end
  end
end
