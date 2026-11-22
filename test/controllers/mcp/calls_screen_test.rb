require "test_helper"
require_relative "../../support/mcp_world"

# The MCP calls log follows the list standard: upstream's filter card with
# Search and Clear Search, the table below, and an empty-state line.
class Mcp::CallsScreenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    sign_in user(:admin)
  end

  test "the filter card has Search and Clear Search, and no yellow buttons" do
    call_tool("whoami", user: user(:alpha_member))
    get mcp_calls_path

    assert_select ".card-footer input.btn-primary[value=Search]"
    assert_select ".card-footer a.btn-dark", text: "Clear Search"
    assert_select ".btn-warning", count: 0
    assert_select ".table-responsive tbody tr", 1
  end

  test "a log with no calls says so" do
    get mcp_calls_path

    assert_select "table", count: 0
    assert_select "p.text-muted", text: "Nothing here yet."
  end
end
