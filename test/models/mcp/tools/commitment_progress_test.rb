require "test_helper"
require_relative "../../../support/mcp_commitments_world"

class Mcp::Tools::CommitmentProgressTest < ActiveSupport::TestCase
  include McpCommitmentsWorld

  setup do
    build_mcp_world
    build_mcp_commitments_world
  end

  def progress(viewer, commitment = @shifts, **arguments)
    call_tool("commitment_progress", user: user(viewer), commitment_id: commitment.neat_id, **arguments)
  end

  def rows(viewer, commitment = @shifts, **arguments)
    progress(viewer, commitment, **arguments).value["rows"]
  end

  def names(row)
    row["people"].map { |p| p["name"] }
  end

  test "an admin, a team manager and a listed organizer get a row for each group" do
    [ :admin, :alpha_manager, :organizer ].each do |viewer|
      table = rows(viewer)

      assert_equal 6, table.sum { |row| row["people"].size }, viewer
      assert_includes table.flat_map { |row| names(row) }, "Ward World"
    end
  end

  test "a row has owed, confirmed, planned and remaining" do
    row = rows(:admin).find { |r| names(r) == [ "AlphaMember World" ] }

    assert_equal 2, row["owed"]
    assert_equal 1, row["confirmed"]
    assert_equal 0, row["planned"]
    assert_equal 1, row["remaining"]
    assert_not row["met"]
    assert_equal [ true, 1, 0 ], row["sources"].map { |line| [ line["available"], line["confirmed"], line["planned"] ] }.first
    assert_nil row["records"]
  end

  test "a grouped commitment pools the group's credit and counts the relative" do
    row = rows(:admin).find { |r| names(r).include?("Ward World") }

    assert_equal [ "Sibling World", "Ward World" ], names(row)
    assert_equal [ 3, 2, 1, 1 ], row.values_at("owed", "confirmed", "planned", "remaining")
  end

  test "an adjustment shows to the group, a relative and an organizer, with its reason" do
    [ :organizer, :alpha_manager, :admin ].each do |viewer|
      row = rows(viewer).find { |r| names(r).include?("Ward World") }

      assert_equal [ { "person" => { "id" => person(:ward).neat_id, "name" => "Ward World" }, "credits" => 1, "reason" => "Covered a shift" } ],
        row["adjustments"], viewer
    end
    [ :ward, :guardian ].each do |viewer|
      assert_equal [ "Covered a shift" ], rows(viewer).sole["adjustments"].map { |a| a["reason"] }, viewer
    end
  end

  test "a relative's check-in is a record naming them and a planned one reads as planned" do
    records = rows(:ward).sole["records"]

    assert_equal [ [ "Checked in: Parent Shift", true, "Guardian World" ], [ "Checked in: Next Shift", false, "Ward World" ] ],
      records.map { |r| [ r["label"], r["confirmed"], r["person"]["name"] ] }
  end

  test "a member outside the group sees no adjustment" do
    assert_equal "Not found", progress(:alpha_member, person_id: person(:ward).neat_id).error
    assert_empty rows(:alpha_member).sole["adjustments"]
  end

  test "a friend, through another relationship type, is not a group relative" do
    assert_equal "Not found", progress(:beta_member).error
    assert_equal "Not found", progress(:beta_member, person_id: person(:alpha_member).neat_id).error
  end

  test "an organizer on the list whose grant lapsed gets only their own row" do
    result = rows(:lapsed)

    assert_equal [ [ "Lapsed World" ] ], result.map { |row| names(row) }
    assert_empty result.sole["records"]
  end

  test "a badge-limited commitment has rows only for badge holders" do
    badge = create_world_badge("Limit")
    BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    limited = Commitment.create!(title: "Limited", team: @alpha, owing_team: @alpha, owing_badge: badge, base_amount: 5, unit: "shifts",
      starts_on: Date.current, ends_on: 1.month.from_now.to_date)

    assert_equal [ [ "AlphaMember World" ] ], rows(:admin, limited).map { |row| names(row) }
    assert_equal "Not found", progress(:admin, limited, person_id: person(:ward).neat_id).error
  end

  test "an exempt holder has no row, even for a manager" do
    badge = create_world_badge("Exempt")
    BadgeAssignment.create!(badge: badge, person: person(:alpha_member))
    exempt = Commitment.create!(title: "Exempt", team: @alpha, owing_team: @alpha, exempt_badge: badge, base_amount: 1, unit: "shifts",
      starts_on: Date.current, ends_on: 1.month.from_now.to_date)

    assert_not_includes rows(:alpha_manager, exempt).flat_map { |row| names(row) }, "AlphaMember World"
    assert_equal "Not found", progress(:alpha_manager, exempt, person_id: person(:alpha_member).neat_id).error
  end

  test "a source's cap and ratio explain the confirmed credit" do
    capped = Commitment.create!(title: "Capped", team: @alpha, owing_team: @alpha, base_amount: 3, unit: "shifts",
      starts_on: 1.month.ago.to_date, ends_on: 1.month.from_now.to_date)
    capped.commitment_sources.create!(kind: "checkins", subject: event_types(:one), per: 2, credits: 1, max_credits: 1)
    3.times { |i| create_world_checkin(person(:alpha_member), create_world_event("Cap #{i}", @alpha, (i + 1).days.ago)) }
    row = rows(:admin, capped, person_id: person(:alpha_member).neat_id).sole
    source = row["sources"].sole

    assert_equal 1, row["confirmed"]
    assert_equal 4, row["records"].size
    assert_equal [ 2, 1, 1, true ], source.values_at("per", "credits_per", "max_credits", "capped")
  end

  test "a relative who doesn't owe can ask about themselves" do
    row = rows(:guardian, person_id: person(:guardian).neat_id).sole

    assert_includes names(row), "Ward World"
  end

  test "filter narrows an organizer's table before the limit" do
    create_world_checkin(person(:alpha_member), create_world_event("Second Shift", @alpha, 1.day.ago))
    names_for = ->(filter) { rows(:admin, filter: filter).flat_map { |row| names(row) } }

    assert_equal [ "AlphaMember World" ], names_for.("met")
    assert_not_includes names_for.("not_met"), "AlphaMember World"
    assert_equal 4, rows(:admin, filter: "not_met").size
    assert_equal [ "AlphaManager World", "Lapsed World", "Organizer World" ], names_for.("nothing_planned").sort
    assert_equal 1, progress(:admin, filter: "not_met", limit: 1).value["rows"].size
    assert progress(:admin, filter: "not_met", limit: 1).value["truncated"]
  end

  test "filter is ignored outside the organizers' table" do
    assert_equal 1, rows(:alpha_member, filter: "met").size
  end

  test "a filter value outside the page's is refused" do
    assert_match(/filter/i, progress(:admin, filter: "bogus").error)
  end

  test "an organizer asking for one person gets the credits and where each came from" do
    row = rows(:organizer, person_id: person(:alpha_member).neat_id).sole

    assert_equal [ "AlphaMember World" ], names(row)
    assert_equal [ [ "Checked in: Past Shift", true, "AlphaMember World" ] ],
      row["records"].map { |record| [ record["label"], record["confirmed"], record["person"]["name"] ] }
  end

  test "a member who owes sees only their own row" do
    result = rows(:alpha_member)

    assert_equal 1, result.size
    assert_equal [ "AlphaMember World" ], names(result.first)
    assert_equal 1, result.first["records"].size
  end

  test "a member can't ask for another member" do
    assert_equal "Not found", progress(:alpha_member, person_id: person(:ward).neat_id).error
    assert_equal "Not found", progress(:ward, person_id: person(:alpha_member).neat_id).error
  end

  test "a relative in the group sees the group's progress and may ask for the member" do
    result = rows(:guardian)

    assert_equal [ [ "Sibling World", "Ward World" ] ], result.map { |row| names(row) }
    assert_equal 1, rows(:guardian, person_id: person(:ward).neat_id).size
    assert_equal "Not found", progress(:guardian, person_id: person(:alpha_member).neat_id).error
  end

  test "an unrelated member can't see the commitment" do
    assert_equal "Not found", progress(:beta_member).error
    assert_equal "Not found", progress(:beta_member, person_id: person(:alpha_member).neat_id).error
  end

  test "a person who doesn't owe the commitment is not found, even for an admin" do
    assert_equal "Not found", progress(:admin, person_id: person(:beta_member).neat_id).error
    assert_equal "Not found", progress(:admin, person_id: "per_nope").error
  end

  test "a commitment that isn't there is not found" do
    assert_equal "Not found", call_tool("commitment_progress", user: user(:admin), commitment_id: "cmt_nope").error
  end

  test "limit truncates the rows" do
    result = progress(:admin, limit: 1).value

    assert_equal 1, result["rows"].size
    assert result["truncated"]
  end

  test "it is off with the commitments feature" do
    with_feature(:commitments, false) do
      assert_equal "Feature off", progress(:admin).error
      assert_not_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "commitment_progress"
    end
  end
end
