require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListCalendarNotesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    CalendarNote.delete_all
    @general = note("General", Time.utc(2026, 3, 10, 12))
    @alpha_note = note("Alpha note", Time.utc(2026, 3, 11, 12), noteable: @alpha, description: "Bring tools")
    @beta_note = note("Beta note", Time.utc(2026, 3, 12, 12), noteable: @beta)
    @person_note = note("On a person", Time.utc(2026, 3, 13, 12), noteable: person(:alpha_member))
    @outside = note("Outside", Time.utc(2026, 5, 1, 12))
    @running = note("Running", Time.utc(2026, 2, 1, 12), ends: Time.utc(2026, 3, 2, 12))
  end

  def note(name, start, noteable: nil, description: nil, ends: nil)
    CalendarNote.create!(name: name, start_time: start, end_time: ends, noteable: noteable, description: description)
  end

  def names(viewer, **options)
    call_tool("list_calendar_notes", user: user(viewer), from: "2026-03-01", to: "2026-03-31", **options).value["items"].map { |item| item["name"] }
  end

  test "an admin sees all of them in the window, including one already running, oldest first" do
    assert_equal [ "Running", "General", "Alpha note", "Beta note", "On a person" ], names(:admin)
  end

  test "a team manager and a member see their team's, general notes, and notes on teammates" do
    assert_equal [ "Running", "General", "Alpha note", "On a person" ], names(:alpha_manager)
    assert_equal [ "Running", "General", "Alpha note", "On a person" ], names(:ward)
  end

  test "a plain member on another team doesn't see this team's" do
    assert_equal [ "Running", "General", "Beta note" ], names(:beta_member)
  end

  test "a guardian on no team sees general notes" do
    assert_equal [ "Running", "General" ], names(:guardian)
  end

  test "it lists what the calendar's feed lists" do
    %i[admin alpha_member beta_member guardian].each do |viewer|
      sign_in user(viewer)
      get "/calendar/calendar.json", params: { notes: "1", start_time: "2026-03-01T00:00:00Z", end_time: "2026-03-31T23:59:59Z" }
      sign_out user(viewer)

      assert_equal response.parsed_body.map { |item| item["title"] }.sort, names(viewer).sort, viewer
    end
  end

  test "items carry the details" do
    item = call_tool("list_calendar_notes", user: user(:admin), from: "2026-03-11", to: "2026-03-11").value["items"].first

    assert_equal({
      "id" => @alpha_note.neat_id,
      "name" => "Alpha note",
      "description" => "Bring tools",
      "start_time" => @alpha_note.start_time.in_time_zone.iso8601,
      "end_time" => nil,
      "noteable" => { "id" => @alpha.neat_id, "name" => "Alpha" }
    }, item)
  end

  test "the person filter matches the feed's" do
    [ [ :admin, :alpha_member ], [ :alpha_manager, :alpha_member ], [ :alpha_manager, :ward ], [ :beta_member, :beta_member ] ].each do |viewer, target|
      sign_in user(viewer)
      get "/calendar/calendar.json", params: { notes: "1", person_id: person(target).id, start_time: "2026-03-01T00:00:00Z", end_time: "2026-03-31T23:59:59Z" }
      sign_out user(viewer)

      assert_equal response.parsed_body.map { |item| item["title"] }.sort, names(viewer, person_id: person(target).neat_id).sort, "#{viewer} on #{target}"
    end
    assert_equal [ "On a person" ], names(:admin, person_id: person(:alpha_member).neat_id)
  end

  test "the person filter can't reach past the viewer's scope" do
    assert_equal "Not found", call_tool("list_calendar_notes", user: user(:guardian), from: "2026-03-01", to: "2026-03-31", person_id: person(:beta_member).neat_id).error
  end

  test "bad windows are refused" do
    {
      [ "soon", "2026-03-31" ] => /from must be a date/,
      [ "2026-03-01", "2026-02-31" ] => /to must be a date/,
      [ "2026-03-31", "2026-03-01" ] => /can't be before/,
      [ "2024-01-01", "2026-01-01" ] => /at most 366 days/
    }.each do |(from, to), error|
      assert_match error, call_tool("list_calendar_notes", user: user(:admin), from: from, to: to).error
    end
    assert_match(/to/, call_tool("list_calendar_notes", user: user(:admin), from: "2026-03-01").error)
  end

  test "the feature being off refuses it" do
    with_feature(:events, false) { assert_equal "Feature off", call_tool("list_calendar_notes", user: user(:admin), from: "2026-03-01", to: "2026-03-31").error }
  end
end
