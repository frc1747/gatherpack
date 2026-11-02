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
    assert_select "tbody tr:first-child code", "search_people"
    assert_includes response.body, "secretname"
  end

  test "an admin filters by user and tool" do
    sign_in user(:admin)

    get mcp_calls_path, params: { q: { user_id_eq: user(:alpha_member).id } }
    assert_select "tbody tr", 1
    assert_select "tbody tr code", "whoami"

    get mcp_calls_path, params: { q: { tool_eq: "search_people" } }
    assert_select "tbody tr", 1
    assert_select "tbody tr code", "search_people"
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

  test "the setup page links to it for admins only" do
    sign_in user(:admin)
    get setup_path
    assert_select "a[href=?]", mcp_calls_path

    sign_out user(:admin)
    sign_in user(:alpha_member)
    get setup_path
    assert_select "a[href=?]", mcp_calls_path, 0
  end
end
