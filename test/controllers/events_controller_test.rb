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
