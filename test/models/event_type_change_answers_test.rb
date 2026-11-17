require "test_helper"

class EventTypeChangeAnswersTest < ActiveSupport::TestCase
  setup do
    @event = events(:one)
    @old_field = checkin_fields(:one)
    @new_type = event_types(:two)
    @new_field = checkin_fields(:two)
    @checkin = checkins(:one)
  end

  test "changing the event type adds blank responses for the new type's fields" do
    assert_nil @checkin.checkin_field_responses.find_by(checkin_field: @new_field)

    @event.update!(event_type: @new_type)

    response = @checkin.checkin_field_responses.find_by(checkin_field: @new_field)
    assert response
    assert_nil response.response
  end

  test "changing the event type keeps the old type's responses" do
    assert_no_difference -> { @checkin.checkin_field_responses.where(checkin_field: @old_field).count } do
      @event.update!(event_type: @new_type)
      Checkin.find(@checkin.id).refresh_fields
    end
    assert_equal [ @new_field ], Checkin.find(@checkin.id).current_field_responses.map(&:checkin_field)
  end

  test "changing the type back restores the original answers" do
    original = checkin_field_responses(:one).response
    @event.update!(event_type: @new_type)
    @event.update!(event_type: event_types(:one))

    checkin = Checkin.find(@checkin.id)
    assert_equal [ @old_field ], checkin.current_field_responses.map(&:checkin_field)
    assert_equal original, checkin.current_field_responses.first.response
  end

  test "updating an event without changing its type leaves responses alone" do
    assert_no_difference -> { CheckinFieldResponse.count } do
      @event.update!(name: "Renamed")
    end
  end

  test "changing the type removes blank responses for the old type's fields" do
    checkin_field_responses(:one).update!(response: nil)

    @event.update!(event_type: @new_type)

    assert_not @checkin.checkin_field_responses.exists?(checkin_field: @old_field)
    assert @checkin.checkin_field_responses.exists?(checkin_field: @new_field)
  end

  test "an unanswered A to B to A change leaves nothing on B, so its field can be deleted" do
    checkin_field_responses(:one).update!(response: nil)

    @event.update!(event_type: @new_type)
    @event.update!(event_type: event_types(:one))

    assert_not @checkin.checkin_field_responses.exists?(checkin_field: @new_field)
    checkin_field_responses(:two).destroy!
    assert_nothing_raised { @new_field.destroy! }
  end

  test "refresh_fields keeps responses for fields the event type no longer has" do
    @event.update_columns(event_type_id: @new_type.id)
    checkin = Checkin.find(@checkin.id)

    assert_no_difference -> { checkin.checkin_field_responses.where(checkin_field: @old_field).count } do
      checkin.refresh_fields
    end
    assert_equal [ @new_field ], checkin.current_field_responses.map(&:checkin_field)
  end

  test "changing to a type with a linked field adds no response for it" do
    person_field = PersonField.create!(name: "Food Allergies", data_type: :string, read_permission: "family", write_permission: "family")
    linked = CheckinField.create!(event_type: @new_type, name: "Allergies", permission: :added_by_manager, person_field: person_field)

    @event.update!(event_type: @new_type)

    assert_not CheckinFieldResponse.exists?(checkin_field: linked)
    assert @checkin.checkin_field_responses.exists?(checkin_field: @new_field)
  end

  test "fields added to the new type after the change still reach a new check-in" do
    event = Event.find(@event.id)
    later_type = EventType.create!(name: "Later fields")
    event.update!(event_type: later_type)
    field = CheckinField.create!(event_type: later_type, name: "Added later", permission: :added_by_user)

    checkin = Checkin.create!(person: Person.create!(first_name: "Lena", last_name: "Later"), event: event)

    assert checkin.checkin_field_responses.exists?(checkin_field: field)
  end
end
