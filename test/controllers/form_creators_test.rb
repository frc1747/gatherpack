require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Form creators: holders of the badge named in forms_creator_badge (say,
# student leaders) create event forms for their own teams and run only the
# forms they created.
class FormCreatorsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @creator_badge = create_world_badge("Student Leader")
    BadgeAssignment.create!(badge: @creator_badge, person: person(:a1))
    @event = Event.create!(name: "Den A Pizza Night", event_type: event_types(:one), team: @den_a, start_time: 3.days.from_now)
    @mentor_form = create_world_form("Mentor Poll", team: @den_a, include: [ @den_a ], event: @event, created_by: person(:den_a_leader))
  end

  test "a creator makes an event form for their own team, and only an event form" do
    with_creators do
      as(:a1) do
        get forms_path
        assert_select "a", text: "New Form"

        post forms_path, params: { form: { title: "No Event", team_id: @den_a.id, respond_permission: "family", read_permission: "family" } }
        assert_nil Form.find_by(key: "no_event"), "a creator can't make a form without an event"

        den_b_event = Event.create!(name: "Den B Night", event_type: event_types(:one), team: @den_b, start_time: 2.days.from_now)
        post forms_path, params: { form: { title: "Other Den", team_id: @den_b.id, event_id: den_b_event.id, respond_permission: "family", read_permission: "family" } }
        assert_nil Form.find_by(key: "other_den"), "not for a team they don't belong to"

        post forms_path, params: { form: { title: "Pizza Poll", team_id: @den_a.id, event_id: @event.id, respond_permission: "family", read_permission: "family" } }
        form = Form.find_by!(key: "pizza_poll")
        assert_equal person(:a1), form.created_by
        assert_redirected_to edit_form_path(form, tab: "questions")

        patch form_path(form), params: { tab: "details", form: { event_id: "" } }
        assert_equal @event, form.reload.event, "it stays an event form"
      end
    end
  end

  test "a creator runs only the forms they created" do
    with_creators do
      own = create_world_form("Pizza Poll", team: @den_a, include: [ @den_a ], event: @event, created_by: person(:a1))
      add_choice(own, "Pizza", %w[ Cheese Pepperoni ])
      respond(own, :a2, as: :a2, answers: { "pizza" => "Cheese" })

      assert FormPolicy.new(person(:a1).user, own).manage?
      assert_not FormPolicy.new(person(:a1).user, @mentor_form).manage?
      assert FormAccess.new(person(:a1), person(:a2), own).can_read?, "they see responses to their own form"
      assert_not FormAccess.new(person(:a1), person(:a2), @mentor_form).can_read?
      assert_equal own.reachable_subjects.ids.sort, own.readable_subjects_for(person(:a1)).ids.sort

      as(:a1) do
        get forms_path
        assert_select "a", text: "Pizza Poll"
        assert_select "a", text: "Mentor Poll", count: 0
        get edit_form_path(@mentor_form)
        assert_redirected_to root_path
        get results_form_path(own)
        assert_select "td", text: "Cheese"
      end
    end
  end

  test "creators can't add signatures or profile questions, and only ask their own teams" do
    with_creators do
      own = create_world_form("Pizza Poll", team: @den_a, include: [ @den_a ], event: @event, created_by: person(:a1))
      as(:a1) do
        get edit_form_path(own, tab: "questions")
        assert_select "a", text: "Add a signature", count: 0

        post form_questions_path(own), params: { form_question: { kind: "signature", label: "Parent", signer: "guardian" } }
        assert_empty own.form_questions.reload

        with_settings(feature_person_fields: "true") do
          field = create_world_field("Shirt Size", read: "family", write: "family")
          post form_questions_path(own), params: { form_question: { kind: "input", label: "Shirt", person_field_id: field.id, profile_mode: "prefill" } }
          assert_empty own.form_questions.reload
        end

        post form_audience_rules_path(own), params: { form_audience_rule: { effect: "include", target_type: "team", team_id: @pack.id } }
        assert own.form_audience_rules.exists?(team: @pack), "a team above their own is one they belong to"
        post form_audience_rules_path(own), params: { form_audience_rule: { effect: "include", target_type: "team", team_id: @den_b.id } }
        assert_not own.form_audience_rules.exists?(team: @den_b)
      end
    end
  end

  test "without the badge, the setting, or Badges, a creator is just a member" do
    own = create_world_form("Pizza Poll", team: @den_a, include: [ @den_a ], event: @event, created_by: person(:a1))
    assert_not FormPolicy.new(person(:a1).user, own).manage?, "no setting"
    with_creators do
      assert_not FormPolicy.new(person(:a2).user, Form.new(team: @den_a, event: @event)).create?, "no badge"
      with_settings(feature_badges: "false") do
        assert_not FormPolicy.new(person(:a1).user, own).manage?, "Badges off"
      end
      BadgeAssignment.find_by!(badge: @creator_badge, person: person(:a1)).destroy!
      assert_not FormPolicy.new(person(:a1).user, own).manage?, "badge removed"
    end
  end

  test "a badge members can give themselves can't make form creators" do
    @creator_badge.update!(permission: :added_by_current_member, team: @den_a)
    with_creators { assert_nil Form.creator_badge }
  end

  private

  def with_creators(&block)
    with_settings(feature_forms: "true", forms_creator_badge: "student leader", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
