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
    assert_equal false, value["can_write"]
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

  # setting, token's scopes => writes_enabled (the setting), can_write (both)
  {
    [ "false", "mcp_read" ] => [ false, false ],
    [ "false", "mcp_write" ] => [ false, false ],
    [ "false", "mcp_read mcp_write" ] => [ false, false ],
    [ "true", "mcp_read" ] => [ true, false ],
    [ "true", "mcp_write" ] => [ true, true ],
    [ "true", "mcp_read mcp_write" ] => [ true, true ]
  }.each do |(setting, scopes), expected|
    test "with mcp_write_enabled #{setting} and scopes #{scopes}, whoami says #{expected}" do
      with_settings(mcp_write_enabled: setting) do
        value = call_tool("whoami", user: user(:admin), scopes: scopes).value

        assert_equal expected, value.values_at("writes_enabled", "can_write")
      end
    end
  end

  test "the description tells a client when to reconnect" do
    assert_match(/writes_enabled is true and can_write is false, disconnect and reconnect/, Mcp::Tools::Whoami.description)
  end

  test "the setting's description says connected clients must reconnect" do
    assert_match(/Clients connected while this was off must reconnect to make changes/, Settings.get(:mcp_write_enabled).description)
  end

  test "returns no contact details" do
    assert_not_includes call_tool("whoami", user: user(:alpha_member)).value.to_json, user(:alpha_member).email
  end
end
