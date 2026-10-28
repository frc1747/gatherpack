require "test_helper"

class CheckinPolicyTest < ActiveSupport::TestCase
  setup do
    # Org (run by @org_leader)
    # ├── Team A (run by @lead_a; @student, @attendee)
    # └── Team B (run by @lead_b)
    org = Team.create!(name: "Org", team_type: team_types(:one))
    team_a = Team.create!(name: "Team A", team_type: team_types(:one), parent: org)
    team_b = Team.create!(name: "Team B", team_type: team_types(:one), parent: org)

    @admin = create_user("admin", admin: true)
    @org_leader = create_user("org-leader", team: org, manager: true)
    @lead_a = create_user("lead-a", team: team_a, manager: true)
    @lead_b = create_user("lead-b", team: team_b, manager: true)
    @student = create_user("student", team: team_a)
    @attendee = create_user("attendee", team: team_a)

    event = Event.create!(name: "A practice", start_time: 1.day.from_now, event_type: event_types(:one), team: team_a)
    @checkin = Checkin.create!(event: event, person: @attendee.person, notes: "Left early")
  end

  test "the event's managers, admins and the person checked in may see a check-in's notes" do
    assert CheckinPolicy.new(@admin, @checkin).show_notes?
    assert CheckinPolicy.new(@org_leader, @checkin).show_notes?
    assert CheckinPolicy.new(@lead_a, @checkin).show_notes?
    assert CheckinPolicy.new(@attendee, @checkin).show_notes?
  end

  test "other members and other teams' managers may not see a check-in's notes" do
    assert_not CheckinPolicy.new(@student, @checkin).show_notes?
    assert_not CheckinPolicy.new(@lead_b, @checkin).show_notes?
  end

  private

  def create_user(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    user
  end
end
