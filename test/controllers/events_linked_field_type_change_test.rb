require "test_helper"
require_relative "../support/person_fields_world"

# Linked check-in fields show a person's value, so a field from the event's
# previous type mustn't reach any screen once the type has changed.
class EventsLinkedFieldTypeChangeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld

  setup do
    host! "localhost"
    build_person_fields_world
    allergies = create_world_field("Food Allergies", read: "family", write: "family")
    person(:a1).set_field_value(allergies, "peanut")

    old_type = EventType.create!(name: "Campout")
    @old_linked = CheckinField.create!(event_type: old_type, name: "Old Allergies", permission: :added_by_manager, person_field: allergies)
    new_type = EventType.create!(name: "Meeting")
    @new_linked = CheckinField.create!(event_type: new_type, name: "New Allergies", permission: :added_by_manager, person_field: allergies)
    @event = Event.create!(name: "Spring Campout", event_type: old_type, team: @den_a, start_time: 1.day.from_now, end_time: 2.days.from_now)
    @checkin = Checkin.create!(person: person(:a1), event: @event)
    @event.update!(event_type: new_type)
  end

  test "print groups by a current linked field" do
    as(:den_a_leader) { get print_event_path(@event, field_id: @new_linked.id) }

    assert_response :success
    assert_select "h2", text: /peanut \[1\]/
  end

  test "print ignores a linked field from the previous type" do
    as(:den_a_leader) { get print_event_path(@event, field_id: @old_linked.id) }

    assert_response :success
    assert_not_includes response.body, "peanut"
  end

  test "arrange ignores linked fields" do
    [ @old_linked, @new_linked ].each do |field|
      as(:den_a_leader) { get arrange_event_path(@event, field_id: field.id) }

      assert_response :success
      assert_select "h2", text: /Arranging by/, count: 0
    end
  end

  test "the check-in page lists only the current type's linked field" do
    as(:den_a_leader) { get event_checkin_path(@event, @checkin) }

    assert_response :success
    assert_includes response.body, "New Allergies"
    assert_includes response.body, "peanut"
    assert_not_includes response.body, "Old Allergies"
  end

  private

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
