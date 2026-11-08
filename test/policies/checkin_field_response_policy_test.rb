require "test_helper"

class CheckinFieldResponsePolicyTest < ActiveSupport::TestCase
  setup do
    # Team A (run by @lead_a; @student, @attendee)
    team_a = Team.create!(name: "Team A", team_type: team_types(:one))

    @admin = create_user("admin", admin: true)
    @lead_a = create_user("lead-a", team: team_a, manager: true)
    @student = create_user("student", team: team_a)
    @attendee = create_user("attendee", team: team_a)

    event_type = EventType.create!(name: "Practice")
    @admin_field = CheckinField.create!(event_type: event_type, name: "Dues paid", permission: :added_by_admin)
    @manager_field = CheckinField.create!(event_type: event_type, name: "Group", permission: :added_by_manager)
    @open_field = CheckinField.create!(event_type: event_type, name: "Carpool seats", permission: :added_by_user)
    event = Event.create!(name: "Practice", start_time: 1.hour.ago, event_type: event_type, team: team_a)
    @checkin = Checkin.create!(event: event, person: @student.person)
  end

  test "the person checked in writes the fields open to them on their own check-in" do
    assert CheckinFieldResponsePolicy.new(@student, response_for(@open_field)).update?
    assert_not CheckinFieldResponsePolicy.new(@student, response_for(@manager_field)).update?
    assert_not CheckinFieldResponsePolicy.new(@student, response_for(@admin_field)).update?
  end

  test "managers write manager fields and admins every field" do
    assert CheckinFieldResponsePolicy.new(@lead_a, response_for(@manager_field)).update?
    assert_not CheckinFieldResponsePolicy.new(@lead_a, response_for(@admin_field)).update?
    assert CheckinFieldResponsePolicy.new(@admin, response_for(@admin_field)).update?
  end

  test "nobody writes a field on a check-in they may not edit" do
    assert_not CheckinFieldResponsePolicy.new(@attendee, response_for(@open_field)).update?
  end

  private

  def response_for(field)
    @checkin.checkin_field_responses.find_by!(checkin_field: field)
  end

  def create_user(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    user
  end
end
