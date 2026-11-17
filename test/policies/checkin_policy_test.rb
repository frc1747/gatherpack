require "test_helper"

class CheckinPolicyTest < ActiveSupport::TestCase
  setup do
    # Org (run by @org_leader)
    # ├── Team A (run by @lead_a; @student, @attendee)
    # └── Team B (run by @lead_b; @member_b)
    # Other Org (@outsider)
    org = Team.create!(name: "Org", team_type: team_types(:one))
    team_a = Team.create!(name: "Team A", team_type: team_types(:one), parent: org)
    team_b = Team.create!(name: "Team B", team_type: team_types(:one), parent: org)

    @admin = create_user("admin", admin: true)
    @org_leader = create_user("org-leader", team: org, manager: true)
    @lead_a = create_user("lead-a", team: team_a, manager: true)
    @lead_b = create_user("lead-b", team: team_b, manager: true)
    @student = create_user("student", team: team_a)
    @attendee = create_user("attendee", team: team_a)
    @member_b = create_user("member-b", team: team_b)
    @outsider = create_user("outsider", team: Team.create!(name: "Other Org", team_type: team_types(:one)))

    @event = event = Event.create!(name: "A practice", start_time: 1.day.from_now, event_type: event_types(:one), team: team_a)
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

  test "a member checks in only themselves" do
    assert CheckinPolicy.new(@student, checkin_for(@student)).create?
    assert_not CheckinPolicy.new(@student, checkin_for(@member_b)).create?
    assert_not CheckinPolicy.new(@student, checkin_for(@outsider)).create?
  end

  test "the event's managers check in the people they manage" do
    assert CheckinPolicy.new(@lead_a, checkin_for(@student)).create?
    assert CheckinPolicy.new(@lead_a, checkin_for(@lead_a)).create?
    assert CheckinPolicy.new(@org_leader, checkin_for(@member_b)).create?
    assert_not CheckinPolicy.new(@lead_a, checkin_for(@member_b)).create?
    assert_not CheckinPolicy.new(@lead_a, checkin_for(@outsider)).create?
  end

  test "another team's manager checks in only themselves" do
    assert CheckinPolicy.new(@lead_b, checkin_for(@lead_b)).create?
    assert_not CheckinPolicy.new(@lead_b, checkin_for(@member_b)).create?
  end

  test "an admin checks in anyone" do
    assert CheckinPolicy.new(@admin, checkin_for(@outsider)).create?
  end

  test "only admins and the event's managers check in on a locked event" do
    @event.update!(locked: true)

    assert_not CheckinPolicy.new(@student, checkin_for(@student)).create?
    assert_not CheckinPolicy.new(@student, @event.checkins.build).new?
    assert_not CheckinPolicy.new(@lead_b, checkin_for(@lead_b)).create?
    assert CheckinPolicy.new(@lead_a, checkin_for(@student)).create?
    assert CheckinPolicy.new(@lead_a, @event.checkins.build).new?
    assert CheckinPolicy.new(@admin, checkin_for(@outsider)).create?
  end

  private

  def checkin_for(user)
    @event.checkins.build(person: user.person)
  end

  def create_user(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    user
  end
end
