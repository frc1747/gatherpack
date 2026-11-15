require "test_helper"
require_relative "../../support/mcp_world"

class Mcp::MinorRuleTest < ActiveSupport::TestCase
  include McpWorld

  def minor?(birthday)
    Mcp::MinorRule.minor?(Person.new(birthday: birthday))
  end

  test "someone with no birthday on file counts as a minor" do
    assert minor?(nil)
  end

  test "a person turns 18 on the birthday itself, not the day before" do
    travel_to Time.utc(2026, 5, 6, 12) do
      assert_not minor?(Date.new(2008, 5, 6))
      assert minor?(Date.new(2008, 5, 7))
      assert_not minor?(Date.new(2008, 5, 5))
    end
  end

  test "someone born on February 29 turns 18 on March 1" do
    travel_to(Time.utc(2026, 2, 28, 12)) { assert minor?(Date.new(2008, 2, 29)) }
    travel_to(Time.utc(2026, 3, 1, 12)) { assert_not minor?(Date.new(2008, 2, 29)) }
  end

  test "today being February 29 is an ordinary date" do
    travel_to Time.utc(2028, 2, 29, 12) do
      assert_not minor?(Date.new(2010, 2, 28))
      assert_not minor?(Date.new(2010, 2, 28) - 1.day)
      assert minor?(Date.new(2010, 3, 1))
    end
  end

  test "today is taken in the app's time zone, whatever zone the caller is in" do
    birthday = Date.new(2008, 3, 12)

    # March 11 in UTC, already March 12 in Auckland.
    travel_to Time.utc(2026, 3, 11, 12) do
      with_settings(time_zone: "Etc/UTC") { assert minor?(birthday) }
      with_settings(time_zone: "Pacific/Auckland") { assert_not minor?(birthday) }
    end

    # March 12 in UTC, still March 11 in Honolulu.
    travel_to Time.utc(2026, 3, 12, 5) do
      with_settings(time_zone: "Etc/UTC") { assert_not minor?(birthday) }
      with_settings(time_zone: "Pacific/Honolulu") do
        assert minor?(birthday)
        Time.use_zone("Etc/UTC") { assert minor?(birthday) }
      end
    end
  end

  test "a birthday more than 120 years ago counts as unknown, so it fails closed" do
    travel_to Time.utc(2026, 5, 6, 12) do
      assert minor?(Date.new(10, 5, 6))
      assert minor?(Date.new(26, 5, 6))
      assert minor?(Date.new(1906, 5, 5))
      assert_not minor?(Date.new(1906, 5, 6))
      assert_not minor?(Date.new(1950, 5, 6))
    end
  end

  test "a birthday in the future counts as a minor" do
    assert minor?(Date.current + 1.year)
  end

  test "Mcp.withhold_contact_details? is the rule" do
    assert Mcp.withhold_contact_details?(Person.new)
    assert Mcp.withhold_contact_details?(Person.new(birthday: 16.years.ago.to_date))
    assert_not Mcp.withhold_contact_details?(Person.new(birthday: 30.years.ago.to_date))
  end

  test "the withheld keys are profile keys get_person can leave out" do
    assert_empty Mcp::MinorRule::WITHHELD_KEYS - Mcp::Tools::GetPerson::PROFILE_FIELD_KEYS
    assert_empty Mcp::MinorRule::WITHHELD_KEYS & Mcp::Tools::GetPerson.output_schema[:required]
  end

  # Audit: get_person is the only core tool that returns these for anyone. Each of
  # the others that names a person is run on a minor with every detail filled in.
  test "no other core tool returns a minor's contact details" do
    build_mcp_world
    build_mcp_time_world
    ward = person(:ward)
    birthday = 16.years.ago.to_date
    ward.update!(phone_number: "555-0100", address: "1 Main St", birthday: birthday)
    create_world_punch(ward, @alpha_period, 34, nil)
    held = BadgeAssignment.create!(badge: @access_badge, person: ward)
    window = { from: "2026-03-01", to: "2026-03-31" }
    admin = user(:admin)

    results = [
      call_tool("whoami", user: user(:ward)),
      call_tool("search_people", user: admin, query: "Ward"),
      call_tool("get_team", user: admin, team_id: @alpha.neat_id),
      call_tool("get_badge", user: admin, badge_id: @access_badge.neat_id),
      call_tool("get_event", user: admin, event_id: @alpha_event.neat_id),
      call_tool("list_checkins", user: admin, person_id: ward.neat_id, **window),
      call_tool("time_clock_hours", user: admin, person_id: ward.neat_id, **window),
      call_tool("clocked_in_now", user: admin),
      call_tool("add_team_member", user: admin, person_id: ward.neat_id, team_id: @beta.neat_id),
      call_tool("record_checkin", user: admin, person_id: ward.neat_id, event_id: @beta_event.neat_id),
      call_tool("remove_badge", user: admin, badge_assignment_id: held.neat_id),
      call_tool("assign_badge", user: admin, person_id: ward.neat_id, badge_id: @access_badge.neat_id),
      call_tool("remove_team_member", user: admin, membership_id: Membership.find_by!(person: ward, team: @beta).neat_id)
    ]

    results.each do |result|
      assert_nil result.error
      json = result.value.to_json
      assert_match(/#{ward.neat_id}|checkin_id/, json)
      [ ward.user.email, "555-0100", "1 Main St", birthday.iso8601 ].each { |value| assert_not_includes json, value }
    end
  end
end
