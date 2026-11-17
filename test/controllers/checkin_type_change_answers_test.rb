require "test_helper"

# Check-in answers for a previous event type are kept but hidden: no screen
# shows them and no request can change them while the event has another type.
class CheckinTypeChangeAnswersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @event = events(:one)
    @old_field = checkin_fields(:one)
    @new_field = checkin_fields(:two)
    @old_field.update!(name: "Old Field Label", permission: :added_by_admin)
    @new_field.update!(name: "New Field Label", permission: :added_by_admin)

    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: member_user, first_name: "Jo", last_name: "Member")
    Membership.create!(person: @member, team: @event.team, manager: false)

    @checkin = Checkin.create!(event: @event, person: @member)
    @old_row = @checkin.checkin_field_responses.find_by!(checkin_field: @old_field)
    @old_row.update!(response: "old-answer-xyz")
    @event.update!(event_type: event_types(:two))
    @new_row = @checkin.reload.checkin_field_responses.find_by!(checkin_field: @new_field)
    @new_row.update!(response: "new-answer-abc")
  end

  test "show hides the previous type's answers" do
    sign_in @admin
    get event_checkin_path(@event, @checkin)

    assert_response :success
    assert_includes response.body, "New Field Label"
    assert_includes response.body, "new-answer-abc"
    assert_not_includes response.body, "Old Field Label"
    assert_not_includes response.body, "old-answer-xyz"
  end

  test "edit hides the previous type's answers and keeps them" do
    sign_in @admin
    get edit_event_checkin_path(@event, @checkin)

    assert_response :success
    assert_includes response.body, "New Field Label"
    assert_includes response.body, "new-answer-abc"
    assert_not_includes response.body, "Old Field Label"
    assert_not_includes response.body, "old-answer-xyz"
    assert_equal "old-answer-xyz", @old_row.reload.response
  end

  test "arrange and print with the previous type's field id show no answers" do
    sign_in @admin
    [ arrange_event_path(@event, field_id: @old_field.id), print_event_path(@event, field_id: @old_field.id) ].each do |path|
      get path
      assert_response :success
      assert_not_includes response.body, "old-answer-xyz"
    end
    assert_equal "old-answer-xyz", @old_row.reload.response
  end

  test "a stale form can't change a hidden answer" do
    sign_in @member.user

    patch event_checkin_path(@event, @checkin), params: { checkin: { checkin_field_responses_attributes: { "0" => { id: @old_row.id, response: "TAMPERED" } } } }

    assert_equal "old-answer-xyz", @old_row.reload.response
  end

  test "a member can't change an answer they lack permission for" do
    sign_in @member.user

    patch event_checkin_path(@event, @checkin), params: { checkin: { checkin_field_responses_attributes: { "0" => { id: @new_row.id, response: "TAMPERED" } } } }

    assert_equal "new-answer-abc", @new_row.reload.response
  end

  test "a member can't move an answer to another field" do
    sign_in @member.user

    patch event_checkin_path(@event, @checkin), params: { checkin: { checkin_field_responses_attributes: { "0" => { id: @new_row.id, checkin_field_id: @old_field.id, response: "SWAPPED" } } } }

    @new_row.reload
    assert_equal @new_field, @new_row.checkin_field
    assert_equal "new-answer-abc", @new_row.response
    assert_equal "old-answer-xyz", @old_row.reload.response
  end

  test "a user with permission can still change a current answer" do
    sign_in @admin

    patch event_checkin_path(@event, @checkin), params: { checkin: { checkin_field_responses_attributes: { "0" => { id: @new_row.id, response: "edited" } } } }

    assert_equal "edited", @new_row.reload.response
  end

  test "field_update changes a current answer" do
    sign_in @admin

    patch field_update_event_path(@event), params: { field_id: @new_row.id, response: "dragged" }, as: :json

    assert_response :no_content
    assert_equal "dragged", @new_row.reload.response
  end

  test "field_update can't change a hidden answer" do
    sign_in @admin

    patch field_update_event_path(@event), params: { field_id: @old_row.id, response: "DRAGGED" }, as: :json

    assert_response :not_found
    assert_equal "old-answer-xyz", @old_row.reload.response
  end

  test "a member can't forge a response without an id on an admin-only field" do
    sign_in @member.user

    assert_no_difference -> { CheckinFieldResponse.count } do
      patch event_checkin_path(@event, @checkin), params: { checkin: { checkin_field_responses_attributes: { "0" => { checkin_field_id: @new_field.id, response: "FORGED" } } } }
    end
    assert_equal [ "new-answer-abc" ], @checkin.checkin_field_responses.where(checkin_field: @new_field).pluck(:response)
  end

  test "a member can't forge a response without an id on a hidden field" do
    sign_in @member.user

    assert_no_difference -> { CheckinFieldResponse.count } do
      patch event_checkin_path(@event, @checkin), params: { checkin: { checkin_field_responses_attributes: { "0" => { checkin_field_id: @old_field.id, response: "FORGED" } } } }
    end
    assert_equal [ "old-answer-xyz" ], @checkin.checkin_field_responses.where(checkin_field: @old_field).pluck(:response)
  end

  test "creating a check-in drops responses for another type's field" do
    sign_in @admin
    other = Person.create!(first_name: "Al", last_name: "Other")

    post event_checkins_path(@event), params: { checkin: { person_id: other.id, checkin_field_responses_attributes: { "0" => { checkin_field_id: @old_field.id, response: "PLANTED" } } } }

    checkin = @event.checkins.find_by!(person: other)
    assert_not checkin.checkin_field_responses.exists?(checkin_field: @old_field)
    assert_equal [ @new_field ], checkin.checkin_field_responses.map(&:checkin_field)
  end

  test "creating a check-in keeps an answer for a current field" do
    sign_in @admin
    other = Person.create!(first_name: "Al", last_name: "Other")

    post event_checkins_path(@event), params: { checkin: { person_id: other.id, checkin_field_responses_attributes: { "0" => { checkin_field_id: @new_field.id, response: "admin-set" } } } }

    checkin = @event.checkins.find_by!(person: other)
    assert_equal [ "admin-set" ], checkin.checkin_field_responses.pluck(:response)
  end
end
