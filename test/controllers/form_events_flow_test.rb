require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormEventsFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @event = Event.create!(name: "Saturday Build", event_type: event_types(:one), team: @den_a, start_time: 3.days.from_now.change(hour: 9))
    @poll = create_world_form("Coming Saturday?", team: @den_a, include: [ @den_a ], respond: "self_and_leaders", read: "family", event: @event)
    @poll.form_questions.create!(kind: :intent, label: "Are you coming?", required: true)
    @meals = create_world_form("Meal Choices", include: [ @pack ])
    @sandwich = add_choice(@meals, "Sandwich", [ "Slim 1", "Slim 4" ])
    respond(@poll, :a1, as: :a1, answers: { "are_you_coming" => "Yes" })
    respond(@meals, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    Checkin.create!(event: @event, person: person(:a2))
  end

  test "leaders see intent against check-ins on the event page; members see their own form" do
    with_feature do
      as(:den_a_leader) do
        get event_path(@event)
        assert_response :success
        assert_select "#event-forms p", text: /Expected: 1 yes/
        assert_select "#event-forms p", text: /Checked in: 1/
        assert_select "#event-forms h4", text: /Said yes, not checked in \(1\)/
        assert_select "#event-forms h4", text: /Checked in without saying yes \(1\)/
      end
      as(:a2) do
        get event_path(@event)
        assert_select "#event-forms a[href=?]", edit_form_response_path(@poll, person(:a2))
        assert_select "#event-forms p", text: /Expected/, count: 0
      end
    end
  end

  test "the fill page offers Yes, Maybe, and No" do
    with_feature do
      as(:a2) do
        get edit_form_response_path(@poll, person(:a2))
        assert_select "input[type=radio][name=?]", "form_response[answers][are_you_coming]", count: 3
      end
    end
  end

  test "the printable list and the event tally" do
    with_feature do
      as(:pack_leader) do
        get print_list_forms_path
        assert_select "select#form_id"
        assert_select "input[name=who]", count: 0, msg: "the form comes first"

        coming = @poll.intent_question
        get print_list_forms_path(form_id: @meals.id, who: "answered", question_id: coming.id, answers: { coming.id => [ "Yes" ] }, question_ids: [ @sandwich.id ])
        assert_response :success
        assert_select "td", text: "A1 World"
        assert_select "td", text: "Slim 4"
        assert_select "input[type=radio][name=who][value=answered][checked]"
        assert_select "select#question_form_id option[selected]", text: "Coming Saturday? (Saturday Build)"
        assert_select "select#question_id_#{@poll.id}:not([disabled]) option[selected][value=?]", coming.id
        assert_select "select#question_id_#{@meals.id}[disabled]"
        assert_select "input[type=checkbox][name=?][value=Yes][checked]", "answers[#{coming.id}][]"
        assert_select ".card-header h2", text: /Saturday Build/
        assert_select ".card-header div", text: /People: 1 who answered Yes to "Are you coming\?" \(Coming Saturday\?\)/
        assert_select ".card-header div", text: /Answers: Meal Choices/

        get print_list_forms_path(form_id: @meals.id, layout: "labels")
        assert_response :success
        assert_select "input[type=radio][name=who][value=asked][checked]"
        assert_select ".card-header div", text: /asked by Meal Choices/

        get print_list_forms_path(form_id: @meals.id, event_id: @event.id, basis: "expected")
        assert_select "td", text: "A1 World", msg: "old basis links keep working"

        get tally_form_path(@meals, who: "answered", question_id: coming.id, answers: { coming.id => [ "Yes" ] })
        assert_response :success
        assert_select "p", text: /1 who answered Yes/

        get tally_form_path(@poll, basis: "checked_in")
        assert_response :success
      end
    end
  end

  test "printable list columns are tick boxes and start over when the form changes" do
    with_feature do
      as(:pack_leader) do
        driver = @meals.form_questions.create!(label: "Can you drive?", data_type: :boolean)
        get print_list_forms_path(form_id: @meals.id)
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", @sandwich.id
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", driver.id
        assert_select "input[type=hidden][name=columns_for][value=?]", @meals.id

        get print_list_forms_path(form_id: @meals.id, columns_for: @meals.id, question_ids: [ driver.id ])
        assert_select "input[type=checkbox][name=?][value=?]:not([checked])", "question_ids[]", @sandwich.id
        assert_select "th", text: "Can you drive?"
        assert_select "th", text: "Sandwich", count: 0

        get print_list_forms_path(form_id: @meals.id, columns_for: @poll.id, question_ids: [ "from-the-other-form" ])
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", @sandwich.id
      end
    end
  end

  test "the event panel's printable list starts from who said yes" do
    with_feature do
      as(:pack_leader) do
        get event_path(@event)
        assert_select "#event-forms a[href=?]", print_list_forms_path(event_id: @event.id, form_id: @poll.id), text: "Printable list for this event"
        get print_list_forms_path(event_id: @event.id, form_id: @poll.id)
        assert_select "select#form_id option[selected][value=?]", @poll.id
        assert_select ".card-header div", text: /People: 1 who answered Yes to "Are you coming\?"/
        assert_select "td", text: "A1 World", msg: "a list of names even with no columns"

        get print_list_forms_path(event_id: @event.id)
        assert_select "input[type=hidden][name=event_id][value=?]", @event.id
        get print_list_forms_path(event_id: @event.id, form_id: @meals.id)
        assert_select "input[type=radio][name=who][value=answered][checked]"
        assert_select "input[type=checkbox][name=?][value=Yes][checked]", "answers[#{@poll.intent_question.id}][]"
      end
    end
  end

  test "a new form from the event page is for that event and asks its team" do
    with_feature do
      as(:den_a_leader) do
        get event_path(Event.create!(name: "Den A Trip", event_type: event_types(:one), team: @den_a, start_time: 1.week.from_now))
        assert_select "a", text: "New form for this event"

        get new_form_path(event_id: @event.id)
        assert_select "select[name=?] option[selected][value=?]", "form[event_id]", @event.id

        post forms_path, params: { form: { title: "Trip Slip", team_id: @den_a.id, event_id: @event.id, respond_permission: "family", read_permission: "family" } }
        form = Form.find_by!(key: "trip_slip")
        assert_equal @event, form.event
        assert_equal @event.start_time, form.closes_at
        assert_equal [ "Include Den A" ], form.form_audience_rules.map(&:description)

        get edit_form_path(form, tab: "questions")
        assert_select "a", text: %(Add "Are you coming?")
      end
    end
  end

  private

  def with_feature(&block)
    with_settings(feature_forms: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
