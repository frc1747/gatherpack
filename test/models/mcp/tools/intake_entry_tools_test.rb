require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/intake_world"

# list_intake_entries, delete_intake_entries and list_waiting_to_finish: what the registration
# page's sign-up tables and Delete selected, and the Waiting to finish page, allow and show.
class Mcp::Tools::IntakeEntryToolsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include IntakeWorld

  setup do
    host! "localhost"
    build_intake_world
    @outsider = create_intake_person("Olive", "Outsider")
    @viewers = { admin: @admin, leader: @leader, juniors_leader: @juniors_leader, outsider: @outsider }
    @riley, = create_intake_entry(first_name: "Riley", last_name: "Rivera", email: "riley@example.com", teams: [ @juniors ])
    @sam, = create_intake_entry(first_name: "Sam", last_name: "Stone", email: "sam@example.com", teams: [ @juniors, @mentors ])
    @riley.update_columns(created_at: 2.hours.ago, created_ip_prefix: "203.0.113.*")
    @sam.update_columns(created_at: 1.hour.ago)
  end

  def tool(name, viewer, **arguments)
    with_intake { call_tool(name, user: @viewers.fetch(viewer).user, **arguments) }
  end

  def page_delete(viewer, *entries)
    sign_in @viewers[viewer].user
    with_intake { delete entries_intake_registration_path(@registration), params: { entry_ids: entries.map(&:id) } }
    sign_out @viewers[viewer].user
  end

  test "list_intake_entries gives the counts by day and who is waiting, newest first, with no email" do
    result = tool("list_intake_entries", :leader, registration_id: @registration.neat_id)

    assert_equal [ @sam.neat_id, @riley.neat_id ], result.value["items"].map { |item| item["id"] }
    sam = result.value["items"].first
    assert_equal "Sam Stone", sam["name"]
    assert_equal %w[Juniors Mentors], sam["teams"].map { |team| team["name"] }.sort
    assert_nil sam["network"]
    assert_equal "203.0.113.*", result.value["items"].last["network"]
    assert_equal [ { "day" => Date.current.iso8601, "started" => 2, "email_confirmed" => 0 } ], result.value["by_day"]
    assert_no_match(/example\.com|@/, result.value.to_json)
  end

  test "list_intake_entries leaves out confirmed sign-ups and kiosk ones with a person, as the page does" do
    @riley.update!(verified_at: Time.current)
    kiosk = @registration.entries.create!(first_name: "Kay", last_name: "Kiosk", email: "kay@example.com", source: :kiosk,
      person: create_intake_person("Kay", "Kiosk"), facts: { "team_ids" => [ @juniors.id ] })

    result = tool("list_intake_entries", :leader, registration_id: @registration.neat_id)
    assert_equal [ @sam.neat_id ], result.value["items"].map { |item| item["id"] }
    assert_equal [ { "started" => 3, "email_confirmed" => 1 } ], result.value["by_day"].map { |row| row.slice("started", "email_confirmed") }
    assert_not_includes result.value["items"].map { |item| item["id"] }, kiosk.neat_id
  end

  test "list_intake_entries limits and says so" do
    result = tool("list_intake_entries", :leader, registration_id: @registration.neat_id, limit: 1)
    assert_equal [ @sam.neat_id ], result.value["items"].map { |item| item["id"] }
    assert result.value["truncated"]
  end

  test "list_intake_entries allows and refuses as the page does" do
    @viewers.each_key do |viewer|
      sign_in @viewers[viewer].user
      with_intake { get intake_registration_path(@registration) }
      page = response.successful?
      sign_out @viewers[viewer].user

      assert_equal page, !tool("list_intake_entries", viewer, registration_id: @registration.neat_id).error?, "#{viewer}"
    end
  end

  test "delete_intake_entries deletes the ticked unconfirmed sign-ups and lists them in the call's records" do
    result = nil
    assert_difference("Intake::Entry.count", -2) do
      result = tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: [ @riley.neat_id, @sam.neat_id ])
    end

    assert_equal [ @riley.neat_id, @sam.neat_id ].sort, result.value["changed"].map { |row| row["id"] }.sort
    assert_empty result.value["skipped"]
    assert_equal [ @riley, @sam ].sort_by(&:id), result.changed_records.sort_by(&:id)
    assert_not result.value["dry_run"]
  end

  test "delete_intake_entries with dry_run changes nothing, and skips what the page ignores, saying why" do
    @riley.update!(verified_at: Time.current)
    kiosk = @registration.entries.create!(first_name: "Kay", last_name: "Kiosk", email: "kay@example.com", source: :kiosk,
      person: create_intake_person("Kay", "Kiosk"), facts: { "team_ids" => [ @juniors.id ] })
    ids = [ @riley, @sam, kiosk ].map(&:neat_id)

    result = nil
    assert_no_difference("Intake::Entry.count") { result = tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: ids, dry_run: true) }
    assert_equal [ @sam.neat_id ], result.value["changed"].map { |row| row["id"] }
    assert_equal [ { "id" => @riley.neat_id, "reason" => "Already confirmed" }, { "id" => kiosk.neat_id, "reason" => "Has a person (kiosk sign-up)" } ].sort_by { |row| row["id"] },
      result.value["skipped"].sort_by { |row| row["id"] }

    assert_difference("Intake::Entry.count", -1) { tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: ids) }
    assert Intake::Entry.exists?(@riley.id)
    assert Intake::Entry.exists?(kiosk.id)
  end

  test "delete_intake_entries deletes what the page's Delete selected deletes" do
    @riley.update!(verified_at: Time.current)
    kiosk = @registration.entries.create!(first_name: "Kay", last_name: "Kiosk", email: "kay@example.com", source: :kiosk,
      person: create_intake_person("Kay", "Kiosk"), facts: { "team_ids" => [ @juniors.id ] })
    page_delete(:leader, @riley, @sam, kiosk)

    # The page took only the unconfirmed one with no person, as the tool did above.
    assert_equal [ @riley.id, kiosk.id ].sort, Intake::Entry.pluck(:id).sort
  end

  test "delete_intake_entries allows and refuses as the page does" do
    @viewers.each_key do |viewer|
      by_page, by_tool = 2.times.map { |i| @registration.entries.create!(first_name: "T#{i}", last_name: viewer.to_s, email: "#{viewer}#{i}@example.com", facts: { "team_ids" => [ @juniors.id ] }) }
      page_delete(viewer, by_page)
      tool("delete_intake_entries", viewer, registration_id: @registration.neat_id, entry_ids: [ by_tool.neat_id ])

      assert_equal Intake::Entry.exists?(by_page.id), Intake::Entry.exists?(by_tool.id), "#{viewer}"
      assert_equal %i[admin leader].include?(viewer), !Intake::Entry.exists?(by_tool.id), "#{viewer}"
    end
  end

  test "delete_intake_entries: another registration's entry, a read token, writes off and a bad ID" do
    other = Intake::Registration.create!(team: @juniors, title: "Join Juniors", opens_at: 1.day.ago, apply_team_ids: [ @juniors.id ])
    other_entry, = create_intake_entry(first_name: "Pat", last_name: "Park", email: "pat@example.com", registration: other)

    assert_refused("Not found", Intake::Entry) { tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: [ other_entry.neat_id ]) }
    assert_refused("Not allowed", Intake::Entry) { tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: [ @riley.neat_id ], scopes: "mcp_read") }
    assert_refused("Writes disabled", Intake::Entry) { tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: [ @riley.neat_id ], writes_enabled: false) }
    assert_refused("Not found", Intake::Entry) { tool("delete_intake_entries", :juniors_leader, registration_id: @registration.neat_id, entry_ids: [ @riley.neat_id ]) }
    assert_refused("Not found", Intake::Entry) { tool("delete_intake_entries", :leader, registration_id: @registration.neat_id, entry_ids: [ @registration.neat_id ]) }
  end

  test "it needs registration on" do
    assert_equal "Feature off", call_tool("delete_intake_entries", user: @leader.user, registration_id: @registration.neat_id, entry_ids: [ @riley.neat_id ]).error
    assert_equal "Feature off", call_tool("list_waiting_to_finish", user: @leader.user, registration_id: @registration.neat_id).error
  end

  # Waiting to finish ---------------------------------------------------

  def kiosk_entry(first_name, days_ago:, needs_guardian: false)
    person = Person.create!(first_name: first_name, last_name: "Fox")
    entry = @registration.entries.create!(first_name: first_name, last_name: "Fox", email: "#{first_name.downcase}@example.com", source: :kiosk,
      person: person, created_at: days_ago.days.ago, facts: { "team_ids" => [ @juniors.id ], "needs_guardian" => needs_guardian })
    [ entry, person ]
  end

  test "list_waiting_to_finish lists kiosk sign-ups oldest first with the page's notes and no email" do
    jamie, jamie_person = kiosk_entry("Jamie", days_ago: 4)
    placeholder = Person.create!(first_name: "Jamie", last_name: "Fox")
    jamie.household_members.create!(person: jamie_person, role: :applicant, facts: { "possible_match_id" => placeholder.id })
    fresh, = kiosk_entry("Fern", days_ago: 0, needs_guardian: true)

    result = tool("list_waiting_to_finish", :leader, registration_id: @registration.neat_id)
    items = result.value["items"]

    assert_equal [ jamie.neat_id, fresh.neat_id ], items.map { |item| item["entry_id"] }
    assert_equal [ "Jamie Fox", true, 4, false, placeholder.neat_id ], [ items[0]["person"]["name"], items[0]["email_not_opened"], items[0]["days_ago"], items[0]["no_guardian_yet"], items[0]["possible_match"]["id"] ]
    assert_equal [ false, true, nil ], [ items[1]["email_not_opened"], items[1]["no_guardian_yet"], items[1]["possible_match"] ]
    assert_equal [ "Juniors" ], items[0]["teams"].map { |team| team["name"] }
    assert_no_match(/example\.com|@/, result.value.to_json)
  end

  test "list_waiting_to_finish states guardian requests without their email" do
    entry, person = kiosk_entry("Fern", days_ago: 1, needs_guardian: true)
    entry.household_members.create!(role: :guardian, facts: { "ward_id" => person.id, "first_name" => "Gail", "last_name" => "Fox", "email" => "gail@example.com" })
    entry.household_members.create!(role: :guardian, guardian_confirmed_at: Time.current, person: create_intake_person("Gus", "Fox"),
      facts: { "ward_id" => person.id, "first_name" => "Gus", "last_name" => "Fox", "email" => "gus@example.com" })
    entry.household_members.create!(role: :guardian, facts: { "ward_id" => person.id, "first_name" => "Gem", "last_name" => "Fox", "manager_confirms" => true })

    result = tool("list_waiting_to_finish", :leader, registration_id: @registration.neat_id)
    requests = result.value["items"].first["guardian_requests"]

    assert_equal [ [ "Gail Fox", "waiting for the guardian to confirm" ], [ "Gus Fox", "confirmed" ], [ "Gem Fox", "waiting for a manager to confirm" ] ].sort,
      requests.map { |row| [ row["name"], row["status"] ] }.sort
    assert_equal false, result.value["items"].first["no_guardian_yet"]
    assert_no_match(/example\.com|@/, result.value.to_json)
  end

  test "list_waiting_to_finish leaves out confirmed kiosk sign-ups and link sign-ups" do
    entry, = kiosk_entry("Jamie", days_ago: 1)
    confirmed, = kiosk_entry("Cory", days_ago: 1)
    confirmed.update!(verified_at: Time.current)

    assert_equal [ entry.neat_id ], tool("list_waiting_to_finish", :leader, registration_id: @registration.neat_id).value["items"].map { |item| item["entry_id"] }
  end

  test "list_waiting_to_finish allows and refuses as the page does" do
    kiosk_entry("Jamie", days_ago: 1)
    @viewers.each_key do |viewer|
      sign_in @viewers[viewer].user
      with_intake { get waiting_intake_registration_path(@registration) }
      page = response.successful?
      sign_out @viewers[viewer].user

      assert_equal page, !tool("list_waiting_to_finish", viewer, registration_id: @registration.neat_id).error?, "#{viewer}"
    end
  end
end
