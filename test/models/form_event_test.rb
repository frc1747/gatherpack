require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormEventTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
    @event = Event.create!(name: "Saturday Build", event_type: event_types(:one), team: @den_a, start_time: 3.days.from_now.change(hour: 9), end_time: 3.days.from_now.change(hour: 15))
    @poll = create_world_form("Coming Saturday?", team: @den_a, include: [ @den_a ], respond: "self_and_leaders", read: "family", event: @event)
    @coming = @poll.form_questions.create!(kind: :intent, label: "Are you coming?")
    @meals = create_world_form("Meal Choices", include: [ @pack ])
    @sandwich = add_choice(@meals, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ])
  end

  def say(form, subject, intent)
    respond(form, subject, as: subject, answers: { "are_you_coming" => intent })
  end

  def check_in(name)
    Checkin.create!(event: @event, person: person(name))
  end

  test "an event form's deadline defaults to the event start, and the event must be the owning team's" do
    assert_equal @event.start_time, @poll.closes_at

    other = Event.create!(name: "Den B Night", event_type: event_types(:one), team: @den_b, start_time: 1.day.from_now)
    form = Form.new(title: "Wrong team", team: @den_a, event: other)
    assert_not form.valid?
    assert form.errors.key?(:event)

    assert Form.new(title: "Pack form", team: @pack, event: @event).valid?, "an event of a team below the owning team is fine"
  end

  test "an intent question answers yes, maybe, or no, once per form" do
    assert_equal FormQuestion::INTENT_CHOICES, @coming.choice_list
    second = @poll.form_questions.build(kind: :intent, label: "Really?")
    assert_not second.valid?

    response = @poll.form_responses.create!(subject: person(:a1))
    submission = response.start_submission!(person(:a1))
    assert_equal({ "are_you_coming" => "isn't one of the choices" }, submission.assign_answers({ "are_you_coming" => "Probably" }, FormAccess.new(person(:a1), person(:a1), @poll)))
  end

  test "intent counts and check-ins are compared, and intent never checks anyone in" do
    say(@poll, :a1, "Yes")
    say(@poll, :a2, "Yes")
    say(@poll, :assistant, "No")
    assert_no_difference -> { Checkin.count } do
      say(@poll, :den_a_leader, "Maybe")
    end

    forms = EventForms.new(@event, viewer: person(:den_a_leader))
    assert_equal @poll, forms.intent_form
    assert_equal({ "Yes" => 2, "Maybe" => 1, "No" => 1, nil => 0 }, forms.intent_counts)
    assert_equal [ person(:a1), person(:a2) ].sort_by(&:id), forms.expected_people.sort_by(&:id)

    check_in(:a1)
    check_in(:assistant)
    forms = EventForms.new(@event, viewer: person(:den_a_leader))
    assert_equal 2, forms.checked_in_count
    assert_equal [ person(:a2) ], forms.yes_not_checked_in
    assert_equal [ person(:assistant) ], forms.checked_in_without_yes
  end

  test "intent counts only cover people whose answer the viewer can see" do
    say(@poll, :a1, "Yes")
    say(@poll, :a2, "Yes")
    forms = EventForms.new(@event, viewer: person(:parent_a1))
    assert_equal [ person(:a1) ], forms.expected_people
  end

  test "the printable list lists expected people's choices, and who has none" do
    say(@poll, :a1, "Yes")
    say(@poll, :a2, "Yes")
    say(@poll, :den_a_leader, "Yes")
    respond(@meals, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    respond(@meals, :den_a_leader, as: :den_a_leader, answers: { "sandwich" => "Slim 4" })

    sheet = FormPrintList.new(form: @meals, event: @event, viewer: person(:pack_leader), basis: "expected", questions: [ @sandwich ])
    assert_equal [ "A1", "DenALeader" ], sheet.listed.map { |line| line.person.first_name }.sort
    assert_equal [ person(:a2) ], sheet.no_choice.map(&:person)
    assert_equal 2, sheet.tally(@sandwich)["Slim 4"]

    check_in(:a2)
    by_check_in = FormPrintList.new(form: @meals, event: @event, viewer: person(:pack_leader), basis: "checked_in", questions: [ @sandwich ])
    assert_empty by_check_in.listed
    assert_equal [ person(:a2) ], by_check_in.no_choice.map(&:person)
  end

  test "the printable list counts people whose answers the viewer can't see without showing them" do
    say(@poll, :a1, "Yes")
    private_meals = create_world_form("Private Meals", include: [ @pack ], respond: "self", read: "self_and_leaders")
    add_choice(private_meals, "Sandwich", [ "Slim 1" ])
    respond(private_meals, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })

    sheet = FormPrintList.new(form: private_meals, event: @event, viewer: person(:parent_a1), basis: "expected")
    assert_equal [ person(:a1) ], sheet.population, "the parent sees A1 said yes"
    assert_empty sheet.listed
    assert_equal [ person(:a1) ], sheet.hidden.map(&:person), "but not A1's meal answers"
  end

  test "expected needs a form asking who's coming" do
    @coming.destroy!
    sheet = FormPrintList.new(form: @meals, event: @event, viewer: person(:pack_leader), basis: "expected")
    assert_not sheet.basis_available?
    assert_empty sheet.population
  end
end
