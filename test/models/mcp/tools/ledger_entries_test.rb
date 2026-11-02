require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::LedgerEntriesTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  def entries(viewer, ledger, **args)
    call_tool("ledger_entries", user: user(viewer), ledger_id: ledger.neat_id, **args)
  end

  def remarks(result)
    result.value["items"].map { |item| item["description"] }
  end

  test "an admin sees a ledger's entries, newest first" do
    result = entries(:admin, @alpha_ledger)

    assert_equal [ "Awaiting payment", "Snacks", "Dues" ], remarks(result)
    assert_equal [ "pending", "final", "final" ], result.value["items"].map { |item| item["status"] }
    assert_equal [ { "cents" => 500, "formatted" => "$5.00" }, { "cents" => -1250, "formatted" => "-$12.50" },
      { "cents" => 5000, "formatted" => "$50.00" } ], result.value["items"].map { |item| item["amount"] }
  end

  test "entries carry tags and their split parent" do
    items = entries(:admin, @beta_ledger).value["items"]

    assert_equal [ [ "Half", [], @beta_ledger.ledger_entries.find_by!(remark: "Beta dues").neat_id ], [ "Beta dues", [ "Dues" ], nil ] ],
      items.map { |item| [ item["description"], item["tags"], item["split_parent"] ] }
  end

  test "a failed entry is marked failed" do
    @alpha_dues.update!(failed: true)

    assert_includes entries(:admin, @alpha_ledger).value["items"].map { |item| item["status"] }, "failed"
  end

  test "a team manager and a plain member see their team's ledger" do
    assert_equal 3, entries(:alpha_manager, @alpha_ledger).value["items"].size
    assert_equal 3, entries(:alpha_member, @alpha_ledger).value["items"].size
  end

  test "a member of another team doesn't find the ledger" do
    assert_equal "Not found", entries(:beta_member, @alpha_ledger).error
    assert_equal "Not found", entries(:alpha_manager, @beta_ledger).error
  end

  test "a guardian in no team doesn't find the ledger, unless they own it" do
    assert_equal "Not found", entries(:guardian, @alpha_ledger).error

    LedgerOwnership.create!(ledger: @alpha_ledger, owner: person(:guardian))
    assert_equal 3, entries(:guardian, @alpha_ledger).value["items"].size
  end

  test "a wrong ID prefix is not found" do
    assert_equal "Not found", call_tool("ledger_entries", user: user(:admin), ledger_id: @alpha.neat_id).error
  end

  test "tag filter ignores case" do
    assert_equal [ "Dues" ], remarks(entries(:admin, @alpha_ledger, tag: "dUES"))
    assert_empty entries(:admin, @alpha_ledger, tag: "Nothing").value["items"]
  end

  test "date filter is on the posting date" do
    today = Time.current.to_date.iso8601

    assert_equal 3, entries(:admin, @alpha_ledger, from: today, to: today).value["items"].size
    assert_empty entries(:admin, @alpha_ledger, from: (Time.current.to_date + 1).iso8601).value["items"]
    assert_empty entries(:admin, @alpha_ledger, to: (Time.current.to_date - 1).iso8601).value["items"]
  end

  test "limit truncates" do
    result = entries(:admin, @alpha_ledger, limit: 2)

    assert_equal 2, result.value["items"].size
    assert result.value["truncated"]
  end

  test "bad dates and missing arguments are refused" do
    assert_equal "from must be a date like 2026-03-31", entries(:admin, @alpha_ledger, from: "x").error
    assert_equal "to can't be before from", entries(:admin, @alpha_ledger, from: "2026-03-31", to: "2026-03-01").error
    assert_equal "Missing required arguments: ledger_id", call_tool("ledger_entries", user: user(:admin)).error
  end

  test "it is off with the ledger feature" do
    with_feature(:ledger, false) { assert_equal "Feature off", entries(:admin, @alpha_ledger).error }
  end

  test "a partial or malformed date is refused" do
    assert_equal "to must be a date like 2026-03-31", entries(:admin, @alpha_ledger, to: "2026-03").error
    assert_equal "from must be a date like 2026-03-31", entries(:admin, @alpha_ledger, from: "9" * 200).error
  end

  test "dates are in the app's time zone" do
    @alpha_dues.update_columns(created_at: Time.utc(2026, 3, 11, 3, 30))
    with_settings(time_zone: "America/Detroit") do
      result = entries(:admin, @alpha_ledger, from: "2026-03-10", to: "2026-03-10")

      assert_equal [ "Dues" ], remarks(result)
      assert_equal "2026-03-10", result.value["items"].sole["date"]
    end
  end
end
