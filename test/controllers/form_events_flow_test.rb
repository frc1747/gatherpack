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

  test "the order sheet and the event tally" do
    with_feature do
      as(:pack_leader) do
        get order_sheet_forms_path(form_id: @meals.id, event_id: @event.id, basis: "expected", question_ids: [ @sandwich.id ])
        assert_response :success
        assert_select "td", text: "A1 World"
        assert_select "td", text: "Slim 4"

        get order_sheet_forms_path(form_id: @meals.id, event_id: @event.id, basis: "checked_in", layout: "labels")
        assert_response :success
        assert_select "h3", text: /No choice on file: 1/

        get tally_form_path(@poll, basis: "checked_in")
        assert_response :success
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
