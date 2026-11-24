require "test_helper"
require_relative "../support/signups_world"

# The Sign-ups panel on an event's page (spec §3.5).
class SignupEventPanelTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker))
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @dessert = @sheet.signup_positions.create!(name: "Dessert", kind: :items, unit: "pies", capacity: 6)
    create_world_signup(@cashier, :student2)
    create_world_signup(@dessert, :student2, quantity: 2)
  end

  teardown do
    @restore_settings&.call
  end

  test "someone who can sign up sees the sheet's positions, how full they are, and names" do
    sign_in person(:student).user

    get event_path(@event)

    assert_response :success
    assert_select "#event_signups a[href=?]", signup_sheet_path(@sheet, anchor: ActionView::RecordIdentifier.dom_id(@event)), text: "Snack Stand"
    assert_select "#event_signups li", text: /Cashier\s+1 of 4 filled\s+: StudentTwo World/
    assert_select "#event_signups li", text: /Dessert\s+2 of 6 pies/
    assert_select "#event_signups a.btn", text: "Sign up"
  end

  test "each sheet is one row with its state in words and one button: Sign up for a member, Open for an organizer" do
    other = create_world_sheet("Cleanup Crew")
    other.signup_positions.create!(name: "Sweeper", capacity: 2)
    sign_in person(:student).user

    get event_path(@event)

    assert_select "#event_signups .card-header", text: "Sign-up sheets"
    assert_select "#event_signups .list-group-flush > .list-group-item", count: 2
    [ @sheet, other ].each do |sheet|
      row = "##{ActionView::RecordIdentifier.dom_id(sheet, :event_panel)}"
      assert_select "#{row} .btn", count: 1
      assert_select "#{row} a.btn.btn-sm.btn-primary", text: "Sign up"
      assert_select row, text: /Taking sign-ups until Oct 24/
    end
    assert_select "#event_signups a", text: /New sign-up sheet/, count: 0
    assert_select "#event_signups .card-footer", count: 0

    sign_in person(:worker).user
    get event_path(@event)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@sheet, :event_panel)} .btn", count: 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(@sheet, :event_panel)} a.btn.btn-sm.btn-outline-secondary[href=?]",
      signup_sheet_path(@sheet, anchor: ActionView::RecordIdentifier.dom_id(@event)), text: "Open"
    assert_select "#event_signups .card-footer a.btn.btn-sm.btn-outline-secondary[href=?]", new_signup_sheet_path(event_id: @event.id),
      text: "New sign-up sheet for this event"
  end

  test "names stay hidden when the sheet shows them to organizers only" do
    @sheet.names_organizers!
    sign_in person(:student).user

    get event_path(@event)
    assert_select "#event_signups li", text: /1 of 4 filled/
    assert_select "#event_signups", text: /StudentTwo World/, count: 0

    sign_in person(:worker).user
    get event_path(@event)
    assert_select "#event_signups", text: /StudentTwo World/
  end

  test "people the sheet isn't open to don't see it" do
    sign_in person(:outsider).user

    get event_path(@event)

    # Another team's event isn't theirs to open, panel and all.
    assert_response :not_found
    assert_select "#event_signups", count: 0
  end

  test "a draft shows only to its organizers, and an archived sheet to no one" do
    @sheet.draft!
    sign_in person(:student).user
    get event_path(@event)
    assert_select "#event_signups", count: 0

    sign_in person(:worker).user
    get event_path(@event)
    assert_select "#event_signups .list-group-item", text: /Not taking sign-ups yet/
    assert_select "#event_signups a.btn", text: "Sign up", count: 0

    @sheet.archived!
    get event_path(@event)
    assert_select "#event_signups .list-group-item", count: 0
    assert_select "#event_signups", text: /Snack Stand/, count: 0

    sign_in person(:student).user
    get event_path(@event)
    assert_select "#event_signups", count: 0
  end

  test "an event on no sheet has no panel for members; people who make sheets see the empty line and New" do
    other = create_world_event("Practice", Time.zone.parse("2026-10-20 18:00"))
    sign_in person(:student).user

    get event_path(other)

    assert_response :success
    assert_select "#event_signups", count: 0

    sign_in person(:worker).user
    get event_path(other)
    assert_response :success
    assert_select "#event_signups .list-group-item", count: 0
    assert_select "#event_signups p.text-muted", text: "No sign-up sheets for this event."
    assert_select "#event_signups .card-footer a[href=?]", new_signup_sheet_path(event_id: other.id), text: "New sign-up sheet for this event"
  end

  test "a sheet started from the event page starts on the event's team and adds the event" do
    sign_in person(:worker).user

    get new_signup_sheet_path(event_id: @event.id)
    assert_response :success
    assert_select "input[type=hidden][name=event_id][value=?]", @event.id
    assert_select "select[name=?] option[selected][value=?]", "signup_sheet[team_id]", @club.id

    assert_difference "SignupSheet.count", 1 do
      post signup_sheets_path, params: { event_id: @event.id, signup_sheet: { title: "Raffle", team_id: @club.id, status: "draft", names_permission: "everyone" } }
    end
    sheet = SignupSheet.find_by!(title: "Raffle")
    assert_redirected_to signup_sheet_path(sheet)
    assert_equal [ @event ], sheet.events.to_a
  end

  test "a new sheet that can't take its event fails with the reason by Team" do
    raffle = { title: "Raffle", status: "draft", names_permission: "everyone" }
    outside = create_world_event("Away Day", Time.zone.parse("2026-10-25 10:00"), team: @other_org)
    sign_in person(:worker).user

    assert_no_difference "SignupSheet.count" do
      post signup_sheets_path, params: { event_id: @event.id, signup_sheet: raffle.merge(team_id: @concessions.id) }
    end
    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", text: "Team must be Club or a team above it to add Game Day to the sheet"
    assert_select "input[type=hidden][name=event_id][value=?]", @event.id

    assert_no_difference "SignupSheet.count" do
      post signup_sheets_path, params: { event_id: outside.id, signup_sheet: raffle.merge(team_id: @club.id) }
    end
    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", text: "Team can't take that event"
  end

  test "a past event offers no New link and a new sheet can't take it" do
    past = create_world_event("Kickoff", Time.zone.parse("2026-10-01 10:00"))
    sign_in person(:worker).user

    get event_path(past)
    assert_response :success
    assert_select "#event_signups", count: 0

    get new_signup_sheet_path(event_id: past.id)
    assert_response :success
    assert_select "input[name=event_id]", count: 0
    assert_select "p", text: /Saving adds/, count: 0

    assert_no_difference "SignupSheet.count" do
      post signup_sheets_path, params: { event_id: past.id, signup_sheet: { title: "Raffle", team_id: @club.id, status: "draft", names_permission: "everyone" } }
    end
    assert_response :unprocessable_entity
    assert_select ".invalid-feedback", text: "Team can't take Kickoff: it has already happened"
    assert_select "input[name=event_id]", count: 0
  end
end
