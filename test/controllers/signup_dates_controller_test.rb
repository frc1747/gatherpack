require "test_helper"
require_relative "../support/signups_world"

# Add dates making new events for a sheet, and organizers changing the
# events their sheet made (spec §3.5, §3.6).
class SignupDatesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker), events: [])
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 2)
  end

  teardown do
    @restore_settings&.call
  end

  test "an organizer who doesn't manage the team adds new dates, which become events of the sheet's team" do
    sign_in person(:worker).user
    assert_not EventPolicy.new(person(:worker).user, Event.new(team: @club)).create?, "the organizer couldn't make these events themselves"

    get new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_response :success
    assert_select "#new_dates input[type=date]", count: SignupSheetEventsController::NEW_ROWS

    assert_difference [ "Event.count", "SignupSheetEvent.count" ], 2 do
      post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: event_types(:two).id, dates: {
        "0" => { date: "2026-10-24", start_time: "10:00", end_time: "14:00", name: "Home game", location: "Field 2" },
        "1" => { date: "2026-11-07", start_time: "", end_time: "", name: "", location: "" },
        "2" => { date: "", start_time: "", end_time: "", name: "", location: "" } } }
    end
    assert_redirected_to edit_signup_sheet_path(@sheet, anchor: "dates")

    home, picnic = @sheet.events.order(:start_time).to_a
    assert_equal [ "Home game", "Field 2", @club, event_types(:two) ], [ home.name, home.location, home.team, home.event_type ]
    assert_equal [ Time.zone.parse("2026-10-24 10:00"), Time.zone.parse("2026-10-24 14:00") ], [ home.start_time, home.end_time ]
    assert_equal "Snack Stand", picnic.name
    assert_equal [ Time.zone.parse("2026-11-07 00:00"), Time.zone.parse("2026-11-07 23:59") ], [ picnic.start_time, picnic.end_time ]
    assert @sheet.signup_sheet_events.all?(&:created_by_sheet?)
    assert_equal event_types(:two), @sheet.reload.event_type
    assert_equal 2, @cashier.signup_slots.count

    get edit_signup_sheet_path(@sheet)
    assert_select "#dates", text: /Sat Nov 7, 2026, time not set yet/
  end

  test "the event type picked last time is picked again" do
    @sheet.update!(event_type: event_types(:two))
    sign_in person(:worker).user

    get new_signup_sheet_signup_sheet_event_path(@sheet)
    assert_select "select[name=dates_event_type_id] option[selected][value=?]", event_types(:two).id
  end

  test "More rows shows the form again with what was typed, saving nothing" do
    sign_in person(:worker).user

    assert_no_difference "Event.count" do
      post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { more: "1", dates_event_type_id: event_types(:one).id,
        dates: { "0" => { date: "2026-10-24", name: "Kept" } } }
    end
    assert_response :success
    assert_select "#new_dates input[type=date]", count: 1 + SignupSheetEventsController::NEW_ROWS
    assert_select "input[name='dates[0][name]'][value=Kept]"
  end

  test "bad rows, no rows or no event type save nothing and say why" do
    sign_in person(:worker).user

    assert_no_difference [ "Event.count", "SignupSheetEvent.count" ] do
      post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: event_types(:one).id,
        dates: { "0" => { date: "2026-10-24", start_time: "10:00" }, "1" => { date: "not a date" } } }
      assert_response :unprocessable_entity
      assert_select ".text-danger", text: /Date isn't a date/

      post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: event_types(:one).id,
        dates: { "0" => { date: "2026-10-24", start_time: "14:00", end_time: "10:00" } } }
      assert_response :unprocessable_entity
      assert_select ".text-danger", text: /cannot be before start time/

      post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: "", dates: { "0" => { date: "2026-10-24" } } }
      assert_select ".alert-danger", text: "Pick an event type."

      post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: event_types(:one).id, dates: { "0" => { date: "" } } }
      assert_select ".alert-danger", text: "Fill in at least one date."
    end
  end

  test "an organizer sets the real time of a date the sheet made, and everyone signed up is told" do
    picnic = add_made_date("2026-11-07 00:00", "2026-11-07 23:59")
    create_world_signup(@cashier, :student, event: picnic)
    clear_enqueued_jobs
    sign_in person(:worker).user
    sheet_event = @sheet.signup_sheet_events.find_by!(event: picnic)

    get edit_signup_sheet_signup_sheet_event_path(@sheet, sheet_event)
    assert_response :success
    assert_select "input[name='date[start_time]']:not([value])"

    patch signup_sheet_signup_sheet_event_path(@sheet, sheet_event), params: { date: { date: "2026-11-07", start_time: "11:00", end_time: "15:00", name: "Picnic lunch", location: "Park" } }
    assert_redirected_to edit_signup_sheet_path(@sheet, anchor: "dates")

    picnic.reload
    assert_equal [ "Picnic lunch", "Park", Time.zone.parse("2026-11-07 11:00"), Time.zone.parse("2026-11-07 15:00") ],
      [ picnic.name, picnic.location, picnic.start_time, picnic.end_time ]
    assert_equal [ email_of(:student) ], enqueued_email_addresses
    assert_match "Time changed", enqueued_emails.first[1]
    assert_equal person(:worker).user.id.to_s, AuditLog.where(item_type: "Event", item_id: picnic.id, event: "update").sole.whodunnit
  end

  test "a bad time when changing a date saves nothing" do
    picnic = add_made_date("2026-11-07 00:00", "2026-11-07 23:59")
    sign_in person(:worker).user
    sheet_event = @sheet.signup_sheet_events.find_by!(event: picnic)

    patch signup_sheet_signup_sheet_event_path(@sheet, sheet_event), params: { date: { date: "2026-11-07", start_time: "15:00", end_time: "11:00", name: "Picnic" } }

    assert_response :unprocessable_entity
    assert_equal Time.zone.parse("2026-11-07 00:00"), picnic.reload.start_time
  end

  test "organizers can't change events a manager made and attached" do
    attached = create_world_event("Practice", Time.zone.parse("2026-10-20 18:00"))
    sheet_event = @sheet.signup_sheet_events.create!(event: attached)
    sign_in person(:worker).user

    get edit_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(sheet_event)} a", text: "Change", count: 0

    get edit_signup_sheet_signup_sheet_event_path(@sheet, sheet_event)
    assert_redirected_to root_path
    patch signup_sheet_signup_sheet_event_path(@sheet, sheet_event), params: { date: { date: "2026-10-20", start_time: "08:00", name: "Mine" } }
    assert_redirected_to root_path
    assert_equal "Practice", attached.reload.name
  end

  test "people who don't run the sheet can't add or change dates" do
    picnic = add_made_date("2026-11-07 00:00", "2026-11-07 23:59")
    sheet_event = @sheet.signup_sheet_events.find_by!(event: picnic)

    [ :student, :concessions_manager, :outsider ].each do |name|
      sign_in person(name).user

      get new_signup_sheet_signup_sheet_event_path(@sheet)
      assert_redirected_to root_path, name.to_s
      get edit_signup_sheet_signup_sheet_event_path(@sheet, sheet_event)
      assert_redirected_to root_path, name.to_s

      assert_no_difference [ "Event.count", "SignupSheetEvent.count" ] do
        post create_dates_signup_sheet_signup_sheet_events_path(@sheet), params: { dates_event_type_id: event_types(:one).id, dates: { "0" => { date: "2026-12-01" } } }
      end
      assert_redirected_to root_path, name.to_s
      patch signup_sheet_signup_sheet_event_path(@sheet, sheet_event), params: { date: { date: "2026-11-07", start_time: "08:00", name: "Mine" } }
      assert_redirected_to root_path, name.to_s
      assert_equal "Picnic", picnic.reload.name
      sign_out :user
    end
  end

  private

  def add_made_date(starts, ends)
    event = Event.create!(name: "Picnic", start_time: Time.zone.parse(starts), end_time: Time.zone.parse(ends), event_type: event_types(:one), team: @club)
    @sheet.signup_sheet_events.create!(event: event, created_by_sheet: true)
    event
  end
end
