require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    # Org (run by @org_leader)
    # ├── Team A (run by @lead_a)
    # └── Team B
    @org = Team.create!(name: "Org", team_type: team_types(:one))
    @team_a = Team.create!(name: "Team A", team_type: team_types(:one), parent: @org)
    @team_b = Team.create!(name: "Team B", team_type: team_types(:one), parent: @org)

    @admin_user = create_user("admin", admin: true)
    @lead_a_user = create_user("lead-a", team: @team_a, manager: true)
    @org_leader_user = create_user("org-leader", team: @org, manager: true)

    @event = Event.create!(name: "A practice", start_time: 1.day.from_now, end_time: 1.day.from_now + 2.hours,
      event_type: event_types(:one), team: @team_a)
  end

  # --- team ---------------------------------------------------------------

  test "a manager cannot move an event into a team they don't manage" do
    sign_in @lead_a_user

    patch event_path(@event), params: { event: { team_id: @team_b.id } }

    assert_equal @team_a.id, @event.reload.team_id, "Team A's manager moved an event into Team B"
    assert_redirected_to root_path
  end

  test "a manager can move an event between two teams they manage" do
    sign_in @org_leader_user

    patch event_path(@event), params: { event: { team_id: @team_b.id } }

    assert_redirected_to event_path(@event)
    assert_equal @team_b.id, @event.reload.team_id
  end

  test "an admin can move an event to any team" do
    other_org = Team.create!(name: "Other Org", team_type: team_types(:one))
    sign_in @admin_user

    patch event_path(@event), params: { event: { team_id: other_org.id } }

    assert_equal other_org.id, @event.reload.team_id
  end

  # --- time clock period --------------------------------------------------

  test "a manager cannot link an event to another team's time clock period" do
    period = create_period("B season", @team_b)
    sign_in @lead_a_user

    patch event_path(@event), params: { event: { time_clock_period_id: period.id } }

    assert_nil @event.reload.time_clock_period_id, "Team A's manager linked an event to Team B's time clock period"
    assert_response :unprocessable_entity
  end

  test "a manager can link an event to their own team's time clock period" do
    period = create_period("A season", @team_a)
    sign_in @lead_a_user

    patch event_path(@event), params: { event: { time_clock_period_id: period.id } }

    assert_redirected_to event_path(@event)
    assert_equal period.id, @event.reload.time_clock_period_id
  end

  # --- show ---------------------------------------------------------------

  test "a member can't open another team's event or read its check-in notes" do
    student = create_user("student", team: @team_a)
    attendee = create_user("attendee-b", team: @team_b)
    event = Event.create!(name: "B practice", start_time: 1.day.ago, event_type: event_types(:one), team: @team_b)
    Checkin.create!(event: event, person: attendee.person, notes: "Sent home early")
    sign_in student

    get event_path(event)

    assert_response :not_found
  end

  test "a member can't open another organization's event or see who checked in" do
    other_org = Team.create!(name: "Other Org", team_type: team_types(:one))
    outsider = create_user("outsider", team: other_org)
    event = Event.create!(name: "Other kickoff", start_time: 1.day.ago, event_type: event_types(:one), team: other_org)
    Checkin.create!(event: event, person: outsider.person, notes: "Outsider note")
    sign_in create_user("student", team: @team_a)

    get event_path(event)

    assert_response :not_found
  end

  test "a member sees their team's check-ins but only their own check-in's notes" do
    student = create_user("student", team: @team_a)
    attendee = create_user("attendee", team: @team_a)
    Checkin.create!(event: @event, person: attendee.person, notes: "Attendee note")
    Checkin.create!(event: @event, person: student.person, notes: "Student note")
    sign_in student

    get event_path(@event)

    assert_response :success
    assert_includes response.body, attendee.person.display_name
    assert_not_includes response.body, "Attendee note"
    assert_includes response.body, "Student note"
  end

  test "a member can't read another member's check-in notes on the check-in page" do
    attendee = create_user("attendee", team: @team_a)
    checkin = Checkin.create!(event: @event, person: attendee.person, notes: "Attendee note")
    sign_in create_user("student", team: @team_a)

    get event_checkin_path(@event, checkin)

    assert_response :success
    assert_not_includes response.body, "Attendee note"
  end

  test "the event's managers and admins read check-in notes" do
    attendee = create_user("attendee", team: @team_a)
    checkin = Checkin.create!(event: @event, person: attendee.person, notes: "Attendee note")

    [ @lead_a_user, @org_leader_user, @admin_user ].each do |user|
      sign_in user
      get event_path(@event)
      assert_includes response.body, "Attendee note", "#{user.email} couldn't read the notes on the event page"
      get event_checkin_path(@event, checkin)
      assert_includes response.body, "Attendee note", "#{user.email} couldn't read the notes on the check-in page"
    end
  end

  test "managers and admins still open the event's other pages" do
    [ @lead_a_user, @admin_user ].each do |user|
      sign_in user
      get edit_event_path(@event)
      assert_response :success
      get arrange_event_path(@event)
      assert_response :success
      get print_event_path(@event)
      assert_response :success
    end
  end

  test "a manager of another team can't edit the event" do
    sign_in create_user("lead-b", team: @team_b, manager: true)

    get edit_event_path(@event)

    assert_response :not_found
  end

  private

  def create_user(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    user
  end

  def create_period(name, team)
    TimeClockPeriod.create!(name: name, team: team, start_time: 1.month.ago, end_time: 1.month.from_now)
  end
end
