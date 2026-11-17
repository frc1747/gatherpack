require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListLedgersTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  def names(viewer)
    call_tool("list_ledgers", user: user(viewer)).value["items"].map { |item| item["name"] }
  end

  test "an admin sees every ledger with team and balance" do
    items = call_tool("list_ledgers", user: user(:admin)).value["items"]
    alpha = items.find { |item| item["name"] == "Alpha Fund" }

    assert_includes names(:admin), "Beta Fund"
    assert_equal({ "id" => @alpha_ledger.neat_id, "name" => "Alpha Fund", "team" => { "id" => @alpha.neat_id, "name" => "Alpha" },
      "balance" => { "cents" => 3750, "formatted" => "$37.50" } }, alpha)
  end

  test "a team manager and a member see their team's ledger" do
    assert_equal [ "Alpha Fund" ], names(:alpha_manager)
    assert_equal [ "Beta Fund" ], names(:beta_member)
  end

  test "a guardian in no team sees no ledgers" do
    assert_empty names(:guardian)
  end

  test "an owner sees the ledger they own" do
    LedgerOwnership.create!(ledger: @alpha_ledger, owner: person(:guardian))

    assert_equal [ "Alpha Fund" ], names(:guardian)
  end

  test "limit truncates" do
    result = call_tool("list_ledgers", user: user(:admin), limit: 1)

    assert_equal 1, result.value["items"].size
    assert result.value["truncated"]
  end

  test "it is off with the ledger feature" do
    with_feature(:ledger, false) { assert_equal "Feature off", call_tool("list_ledgers", user: user(:admin)).error }
  end
end
