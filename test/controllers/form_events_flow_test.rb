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
        follow_redirect!
        assert_response :success
        assert_select "td", text: "A1 World"
        assert_select "td", text: "Slim 4"
        assert_select "input[type=radio][name=who][value=answered][checked]"
        assert_select "select#question_form_id option[selected]", text: "Coming Saturday? (Saturday Build)"
        assert_select "select#question_id_#{@poll.id}:not([disabled]) option[selected][value=?]", coming.id
        assert_select "select#question_id_#{@meals.id}[disabled]"
        assert_select "input[type=checkbox][name=?][value=Yes][checked]", "answers[#{coming.id}][]"
        assert_select "p", text: /People: 1 who answered Yes to "Are you coming\?" \(Coming Saturday\?\)/
        assert_select "h1", text: "Meal Choices"

        get print_list_forms_path(form_id: @meals.id, layout: "labels")
        follow_redirect!
        assert_response :success
        assert_select "turbo-frame#who_to_include[src=?]", form_path(@meals, frame: "who_to_include"), msg: "everyone asked; other choices load when More choices opens"
        assert_select "input[type=radio][name=layout][value=labels][checked]"
        assert_select "#labels.d-print-flex .fw-bold", text: "A1 World"

        get print_list_forms_path(form_id: @meals.id, event_id: @event.id, basis: "expected")
        follow_redirect!
        assert_select "td", text: "A1 World", msg: "old basis links keep working"

        get tally_form_path(@meals, who: "answered", question_id: coming.id, answers: { coming.id => [ "Yes" ] })
        follow_redirect!
        assert_response :success
        assert_select "p", text: /1 who answered Yes/

        get tally_form_path(@poll, basis: "checked_in")
        follow_redirect!
        assert_response :success
      end
    end
  end

  test "printable list columns are tick boxes and start over when the form changes" do
    with_feature do
      as(:pack_leader) do
        driver = @meals.form_questions.create!(label: "Can you drive?", data_type: :boolean)
        get print_list_forms_path(form_id: @meals.id)
        follow_redirect!
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", @sandwich.id
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", driver.id
        assert_select "input[type=hidden][name=columns_for][value=?]", @meals.id

        get print_list_forms_path(form_id: @meals.id, columns_for: @meals.id, question_ids: [ driver.id ])
        follow_redirect!
        assert_select "input[type=checkbox][name=?][value=?]:not([checked])", "question_ids[]", @sandwich.id
        assert_select "th", text: "Can you drive?"
        assert_select "th", text: "Sandwich", count: 0

        get print_list_forms_path(form_id: @meals.id, columns_for: @poll.id, question_ids: [ "from-the-other-form" ])
        follow_redirect!
        assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", @sandwich.id
      end
    end
  end

  test "a long tick list shows every box, in its own order, in columns" do
    with_feature do
      as(:pack_leader) do
        questions = (1..11).map { |number| @meals.form_questions.create!(label: "Note #{number}", data_type: :string) }
        ticked = [ questions[9], questions[10] ]
        get print_list_forms_path(form_id: @meals.id, columns_for: @meals.id, question_ids: ticked.map(&:id))
        follow_redirect!
        assert_response :success

        assert_select "input[type=checkbox][name=?]", "question_ids[]", count: 12
        ticked.each { |question| assert_select "input[type=checkbox][name=?][value=?][checked]", "question_ids[]", question.id }
        values = css_select("input[type=checkbox][name='question_ids[]']").map { |box| box["value"] }
        assert_equal [ @sandwich, *questions ].map { |question| question.id.to_s }, values, "ticking a box doesn't move it"
        assert_select "button", text: /Show all/, count: 0
        assert_select "[hidden] input[type=checkbox]", count: 0
        assert_select "div[style*=columns]"
      end
    end
  end

  test "a long list of answers shows every answer and still picks people by it" do
    with_feature do
      as(:pack_leader) do
        choices = (1..10).map { |number| "Choice #{number}" }
        question = add_choice(@meals, "Shirt", choices)
        get print_list_forms_path(form_id: @meals.id, who: "answered", question_form_id: @meals.id, question_id: question.id, answers: { question.id => [ "Choice 10" ] })
        follow_redirect!
        assert_response :success

        name = "answers[#{question.id}][]"
        assert_select "input[type=checkbox][name=?]", name, count: 10
        assert_select "input[type=checkbox][name=?][value=?][checked]", name, "Choice 10"
        assert_select "button", text: /Show all/, count: 0
      end
    end
  end

  test "a short tick list has no columns" do
    with_feature do
      as(:pack_leader) do
        7.times { |number| @meals.form_questions.create!(label: "Note #{number}", data_type: :string) }
        get print_list_forms_path(form_id: @meals.id)
        follow_redirect!
        assert_response :success

        assert_select "input[type=checkbox][name=?]", "question_ids[]", count: 8
        assert_select "div[style*=columns]", count: 0
      end
    end
  end

  test "profile details have a heading per field group, skipping groups with nothing readable" do
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      as(:pack_leader) do
        contact = PersonFieldGroup.create!(name: "Contact", position: 0)
        medical = PersonFieldGroup.create!(name: "Medical", position: 1)
        secret = PersonFieldGroup.create!(name: "Admin only", position: 2)
        phone = create_world_field("Phone", read: "self_and_leaders", person_field_group: contact)
        allergy = create_world_field("Allergy", read: "self_and_leaders", person_field_group: medical)
        hidden = create_world_field("Salary", read: "admin", person_field_group: secret)

        get print_list_forms_path(form_id: @meals.id)
        follow_redirect!
        assert_response :success

        assert_select "div.fw-bold", text: "Contact", count: 1
        assert_select "div.fw-bold", text: "Medical", count: 1
        assert_select "div.fw-bold", text: "Admin only", count: 0
        assert_select "input[type=checkbox][name=?][value=?]", "field_ids[]", phone.id
        assert_select "input[type=checkbox][name=?][value=?]", "field_ids[]", allergy.id
        assert_select "input[type=checkbox][name=?][value=?]", "field_ids[]", hidden.id, count: 0
      end
    end
  end

  test "Responses on the event's other forms starts from who said yes; the intent form's own Responses doesn't" do
    lunch = create_world_form("Lunch Order", team: @den_a, include: [ @den_a ], respond: "self_and_leaders", read: "family", event: @event)
    with_feature do
      as(:pack_leader) do
        get event_path(@event)
        assert_select "#event-forms a", text: "Printable list for this event", count: 0
        assert_select "#event-forms a.btn[href=?]", form_path(@poll), text: "Responses"
        link = css_select("#event-forms .list-group-item").detect { |row| row.text.include?("Lunch Order") }.at_css("a.btn")
        assert_equal "Responses", link.text

        get link["href"]
        assert_select "h1", text: "Lunch Order"
        assert_select "p", text: /People: 1 who answered Yes to "Are you coming\?"/
        assert_select "td", text: "A1 World", msg: "a list of names even with no columns"
        assert_equal form_path(lunch, event_id: @event.id), link["href"]

        get print_list_forms_path(event_id: @event.id)
        assert_select "input[type=hidden][name=event_id][value=?]", @event.id
        get print_list_forms_path(event_id: @event.id, form_id: @meals.id)
        follow_redirect!
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
