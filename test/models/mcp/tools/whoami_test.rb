require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::WhoamiTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  test "a member sees themselves, their team and no managed teams" do
    value = call_tool("whoami", user: user(:alpha_member)).value

    assert_equal({ "id" => person(:alpha_member).neat_id, "name" => "AlphaMember World" }, value["person"])
    assert_equal false, value["admin"]
    assert_equal [ @alpha.neat_id ], value["teams"].map { |team| team["id"] }
    assert_empty value["managed_teams"]
    assert_equal [ "mcp_read" ], value["scopes"]
    assert_equal false, value["writes_enabled"]
  end

  test "a manager sees the team they manage" do
    value = call_tool("whoami", user: user(:alpha_manager)).value

    assert_equal [ @alpha.neat_id ], value["managed_teams"].map { |team| team["id"] }
  end

  test "an admin is flagged" do
    assert_equal true, call_tool("whoami", user: user(:admin)).value["admin"]
  end

  test "a guardian in no team has no teams" do
    assert_empty call_tool("whoami", user: user(:guardian)).value["teams"]
  end

  test "writes_enabled needs the scope and the setting" do
    assert_equal false, call_tool("whoami", user: user(:admin), scopes: "mcp_write").value["writes_enabled"]
    with_settings(mcp_write_enabled: "true") do
      assert_equal true, call_tool("whoami", user: user(:admin), scopes: "mcp_write").value["writes_enabled"]
      assert_equal false, call_tool("whoami", user: user(:admin), scopes: "mcp_read").value["writes_enabled"]
    end
  end

  test "returns no contact details" do
    assert_not_includes call_tool("whoami", user: user(:alpha_member)).value.to_json, user(:alpha_member).email
  end
end
