require "test_helper"

class CheckinFieldResponseTest < ActiveSupport::TestCase
  setup do
    team = Team.create!(name: "Team A", team_type: team_types(:one))
    @member = Person.create!(first_name: "Sam", last_name: "Test",
      user: User.create!(email: "sam@example.com", password: "Password1!"))
    Membership.create!(person: @member, team: team)

    event_type = EventType.create!(name: "Practice")
    @admin_field = CheckinField.create!(event_type: event_type, name: "Dues paid", permission: :added_by_admin)
    @participant_field = CheckinField.create!(event_type: event_type, name: "Ride home", permission: :added_by_participant)
    @event = Event.create!(name: "Practice", start_time: 1.hour.ago, event_type: event_type, team: team)
  end

  test "a response the acting person may not write keeps its previous value" do
    checkin = Checkin.create!(event: @event, person: @member)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @admin_field)
    response.update!(response: "no")

    checkin.created_by = @member
    response.update!(response: "yes")

    assert_equal "no", response.reload.response
  end

  test "a new check-in drops a response the acting person may not write" do
    checkin = Checkin.create!(event: @event, person: @member, created_by: @member,
      checkin_field_responses_attributes: [ { checkin_field_id: @admin_field.id, response: "yes" } ])

    assert_nil checkin.checkin_field_responses.find_by!(checkin_field: @admin_field).response
  end

  test "a participant fills a participant field while checking in" do
    checkin = Checkin.create!(event: @event, person: @member, created_by: @member,
      checkin_field_responses_attributes: [ { checkin_field_id: @participant_field.id, response: "Bus" } ])

    assert_equal "Bus", checkin.checkin_field_responses.find_by!(checkin_field: @participant_field).response
  end
end
