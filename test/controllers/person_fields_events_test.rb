require "test_helper"
require_relative "../support/person_fields_world"

# Spec section 9: check-in fields that show a person field, and read levels
# on ordinary check-in fields.
class PersonFieldsEventsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld

  setup do
    host! "localhost"
    build_person_fields_world
    @allergies = create_world_field("Food Allergies", read: "family", write: "family")
    @private_note = create_world_field("Private Note", read: "self", write: "self")
    person(:a1).set_field_value(@allergies, "peanut")
    person(:a2).set_field_value(@allergies, "shellfish")
    person(:a1).set_field_value(@private_note, "secret plan")

    @event_type = EventType.create!(name: "Campout")
    @linked = CheckinField.create!(event_type: @event_type, name: "Allergies", permission: :added_by_manager, person_field: @allergies)
    @linked_private = CheckinField.create!(event_type: @event_type, name: "Note", permission: :added_by_manager, person_field: @private_note)
    @medication = CheckinField.create!(event_type: @event_type, name: "Medication", permission: :added_by_manager, read_permission: :self)
    @tent = CheckinField.create!(event_type: @event_type, name: "Tent", permission: :added_by_manager)
    @event = Event.create!(name: "Spring Campout", event_type: @event_type, team: @den_a, start_time: 1.day.from_now, end_time: 2.days.from_now)
    @a1_checkin = Checkin.create!(person: person(:a1), event: @event)
    @a2_checkin = Checkin.create!(person: person(:a2), event: @event)
    set_response(@a1_checkin, @medication, "inhaler at 3pm")
    set_response(@a1_checkin, @tent, "Tent 1")
    set_response(@a2_checkin, @tent, "Tent 2")
  end

  test "linked fields store no responses of their own" do
    @event.checkins.each(&:refresh_fields)

    assert_not CheckinFieldResponse.exists?(checkin_field: @linked)
    assert_equal "peanut", @linked.value_for(@a1_checkin)
  end

  test "the link is fixed once the field exists, and existing fields stay visible to everyone" do
    assert_not @tent.update(person_field: @allergies)
    assert CheckinField.new(event_type: @event_type, name: "New").read_everyone?
  end

  test "the check-in page shows each value only to people allowed to see it" do
    as(:a1) { get event_checkin_path(@event, @a1_checkin) }
    assert_includes response.body, "peanut"
    assert_includes response.body, "secret plan"
    assert_includes response.body, "inhaler at 3pm"

    as(:den_a_leader) { get event_checkin_path(@event, @a1_checkin) }
    assert_includes response.body, "peanut"
    assert_includes response.body, "Tent 1"
    assert_not_includes response.body, "secret plan"
    assert_not_includes response.body, "inhaler"

    as(:a2) { get event_checkin_path(@event, @a1_checkin) }
    assert_includes response.body, "Tent 1"
    assert_not_includes response.body, "peanut"
    assert_not_includes response.body, "inhaler"
  end

  test "the check-in form hides responses the editor can't see" do
    as(:den_a_leader) { get edit_event_checkin_path(@event, @a1_checkin) }

    assert_response :success
    assert_select "label", text: "Tent"
    assert_select "label", text: "Medication", count: 0
    assert_not_includes response.body, "inhaler"
  end

  test "the print sheet groups by a linked field's value, hiding what the viewer can't see" do
    as(:den_a_leader) { get print_event_path(@event, field_id: @linked.id) }
    assert_response :success
    assert_select "h2", text: /peanut \[1\]/
    assert_select "h2", text: /shellfish \[1\]/

    as(:den_a_leader) { get print_event_path(@event, field_id: @linked_private.id) }
    assert_select "h2", text: /— \[2\]/
    assert_not_includes response.body, "secret plan"

    as(:den_a_leader) { get print_event_path(@event, field_id: @medication.id) }
    assert_not_includes response.body, "inhaler"
  end

  test "arranging skips linked fields and responses the viewer can't see" do
    as(:den_a_leader) { get arrange_event_path(@event, field_id: @tent.id) }
    assert_select "select#field_id option", text: "Allergies", count: 0
    assert_includes response.body, "Tent 1"

    as(:den_a_leader) { get arrange_event_path(@event, field_id: @medication.id) }
    assert_not_includes response.body, "inhaler"

    as(:den_a_leader) { get arrange_event_path(@event, field_id: @linked.id) }
    assert_select "h2", text: /Arranging by/, count: 0
  end

  test "a person field used by a check-in field can't be destroyed" do
    @allergies.archive!

    assert_not @allergies.destroy
    assert PersonField.exists?(@allergies.id)
  end

  private

  def set_response(checkin, field, value)
    checkin.refresh_fields
    checkin.checkin_field_responses.find_by!(checkin_field: field).update!(response: value)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
