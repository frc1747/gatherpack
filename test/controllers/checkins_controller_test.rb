require "test_helper"

class CheckinsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    # Team A (run by @lead_a; @student)
    @team_a = Team.create!(name: "Team A", team_type: team_types(:one))

    @admin = create_user("admin", admin: true)
    @lead_a = create_user("lead-a", team: @team_a, manager: true)
    @student = create_user("student", team: @team_a)

    @event_type = EventType.create!(name: "Practice")
    @admin_field = CheckinField.create!(event_type: @event_type, name: "Dues paid", permission: :added_by_admin)
    @open_field = CheckinField.create!(event_type: @event_type, name: "Carpool seats", permission: :added_by_user)
    @event = Event.create!(name: "Practice", start_time: 1.hour.ago, end_time: 1.hour.from_now,
      event_type: @event_type, team: @team_a)
  end

  # --- Check-in field permissions -----------------------------------------

  test "the edit form keeps a field the member may not write unchanged" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @admin_field)
    sign_in @student

    patch event_checkin_path(@event, checkin),
      params: { checkin: { checkin_field_responses_attributes: [ { id: response.id, response: "yes" } ] } }

    assert_nil response.reload.response
  end

  test "the edit form saves a field the member may write" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @open_field)
    sign_in @student

    patch event_checkin_path(@event, checkin),
      params: { checkin: { checkin_field_responses_attributes: [ { id: response.id, response: "3" } ] } }

    assert_equal "3", response.reload.response
  end

  test "the edit form cannot move a response onto a field the member may not write" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @open_field)
    response.update!(response: "yes")
    sign_in @student

    patch event_checkin_path(@event, checkin),
      params: { checkin: { checkin_field_responses_attributes: [ { id: response.id, checkin_field_id: @admin_field.id } ] } }

    assert_equal @open_field.id, response.reload.checkin_field_id
    assert_equal [ nil ], checkin.checkin_field_responses.where(checkin_field: @admin_field).pluck(:response),
      "a member moved their answer onto an admin-only field"
  end

  test "the edit form cannot move a response off a field the member may not write" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @admin_field)
    response.update!(response: "unpaid")
    sign_in @student

    patch event_checkin_path(@event, checkin),
      params: { checkin: { checkin_field_responses_attributes: [ { id: response.id, checkin_field_id: @open_field.id } ] } }

    assert_equal [ "unpaid" ], checkin.checkin_field_responses.where(checkin_field: @admin_field).pluck(:response),
      "a member moved an admin's answer off an admin-only field"
    assert_equal 1, checkin.checkin_field_responses.where(checkin_field: @open_field).count
  end

  test "checking in does not set a field the member may not write" do
    sign_in @student

    post event_checkins_path(@event), params: { checkin: { person_id: @student.person.id,
      checkin_field_responses_attributes: [
        { checkin_field_id: @admin_field.id, response: "yes" },
        { checkin_field_id: @open_field.id, response: "3" }
      ] } }

    checkin = Checkin.find_by!(event: @event, person: @student.person)
    assert_nil checkin.checkin_field_responses.find_by!(checkin_field: @admin_field).response,
      "a member set an admin-only field while checking in"
    assert_equal "3", checkin.checkin_field_responses.find_by!(checkin_field: @open_field).response
  end

  test "an admin sets an admin-only field while checking someone in" do
    sign_in @admin

    post event_checkins_path(@event), params: { checkin: { person_id: @student.person.id,
      checkin_field_responses_attributes: [ { checkin_field_id: @admin_field.id, response: "yes" } ] } }

    checkin = Checkin.find_by!(event: @event, person: @student.person)
    assert_equal "yes", checkin.checkin_field_responses.find_by!(checkin_field: @admin_field).response
  end

  test "field_update refuses a field the member may not write" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @admin_field)
    sign_in @student

    # As the arrange page sends it: a JSON body, with no Accept header.
    patch field_update_event_path(@event), params: { field_id: response.id, response: "yes" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "*/*" }

    assert_nil response.reload.response, "a member set an admin-only field through field_update"
    assert_response :forbidden
  end

  test "field_update saves a field the member may write on their own check-in" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @open_field)
    sign_in @student

    patch field_update_event_path(@event), params: { field_id: response.id, response: "3" }, as: :json

    assert_response :no_content
    assert_equal "3", response.reload.response
  end

  test "field_update refuses someone else's check-in" do
    checkin = Checkin.create!(event: @event, person: @lead_a.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @open_field)
    sign_in @student

    patch field_update_event_path(@event), params: { field_id: response.id, response: "3" }, as: :json

    assert_response :forbidden
    assert_nil response.reload.response
  end

  test "the arrange page lets a manager drag only the responses they may write" do
    open_checkin = Checkin.create!(event: @event, person: @student.person)
    sign_in @lead_a

    get arrange_event_path(@event, field_id: @admin_field.id)
    assert_select "[id=?][draggable=false]", open_checkin.checkin_field_responses.find_by!(checkin_field: @admin_field).id

    get arrange_event_path(@event, field_id: @open_field.id)
    assert_select "[id=?][draggable=true]", open_checkin.checkin_field_responses.find_by!(checkin_field: @open_field).id
  end

  test "an admin sets an admin-only field through field_update" do
    checkin = Checkin.create!(event: @event, person: @student.person)
    response = checkin.checkin_field_responses.find_by!(checkin_field: @admin_field)
    sign_in @admin

    patch field_update_event_path(@event), params: { field_id: response.id, response: "yes" }, as: :json

    assert_response :no_content
    assert_equal "yes", response.reload.response
  end

  private

  def create_user(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    user
  end
end
