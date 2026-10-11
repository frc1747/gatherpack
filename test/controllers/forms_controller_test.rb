require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ], required: true)
  end

  test "forms are off unless the feature is on" do
    as(:admin) { get forms_path }
    assert_redirected_to root_path
  end

  test "a team manager creates a form and adds a question" do
    with_feature do
      as(:den_a_leader) do
        get new_form_path
        assert_response :success

        post forms_path, params: { form: { title: "Den A Campout", team_id: @den_a.id, respond_permission: "family", read_permission: "family" } }
        form = Form.find_by!(key: "den_a_campout")
        assert_redirected_to edit_form_path(form, tab: "questions")
        assert_equal person(:den_a_leader), form.created_by

        post form_questions_path(form), params: { form_question: { kind: "input", label: "Tent buddy", data_type: "string" } }
        assert_redirected_to edit_form_path(form, tab: "questions")
        assert_equal [ "tent_buddy" ], form.form_questions.map(&:key)
      end
    end
  end

  test "people can't manage forms for teams they don't manage" do
    with_feature do
      as(:den_b_leader) do
        post forms_path, params: { form: { title: "Sneaky", team_id: @den_a.id } }
        assert_nil Form.find_by(key: "sneaky")

        patch form_path(@form), params: { form: { title: "Renamed" } }
        post form_questions_path(@form), params: { form_question: { kind: "input", label: "Extra", data_type: "string" } }
      end
      assert_equal "Meal Choices", @form.reload.title
      assert_equal 1, @form.form_questions.count

      as(:a1) do
        get new_form_path
        assert_redirected_to root_path
      end
    end
  end

  test "a guardian fills in, saves, and submits for their child" do
    with_feature do
      as(:parent_a1) do
        get edit_form_response_path(@form, person(:a1))
        assert_response :success
        assert_select "h1", text: "Meal Choices"
        assert_select ".text-muted", text: /For A1 World, filled in by you as their guardian/

        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "Slim 4" } }, save: "1" }
        assert_redirected_to edit_form_response_path(@form, person(:a1))
        response_record = @form.response_for(person(:a1))
        assert response_record.draft?

        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "Big John" } }, submit: "1" }
        assert_redirected_to form_response_path(@form, person(:a1))
        assert response_record.reload.complete?
        assert_equal "Big John", response_record.active_submission.answer(@sandwich)
        assert_equal person(:parent_a1), response_record.active_submission.submitted_by

        get form_response_path(@form, person(:a1))
        assert_response :success
        assert_select "dd", text: /Big John/
        assert_select "a", text: "Update answers"
      end
    end
  end

  test "invalid answers re-render the form with errors" do
    with_feature do
      as(:a1) do
        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "" } }, submit: "1" }
        assert_response :unprocessable_entity
        assert_select ".invalid-feedback, .is-invalid"
      end
    end
  end

  test "updating keeps the active answers until the update is submitted" do
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })
    with_feature do
      as(:a1) do
        get form_response_path(@form, person(:a1))
        assert_select "a", text: "Update answers"
        assert_select "button", text: "Withdraw response"

        assert_no_difference -> { FormSubmission.count } do
          get edit_form_response_path(@form, person(:a1))
        end
        assert_response :success
        assert_select ".alert", text: /Cancel leaves them exactly as they are/

        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "Slim 4" } }, save: "1" }
        get form_response_path(@form, person(:a1))
        assert_select ".alert", text: /Unsubmitted update/
        assert_select "button", text: "Discard update"
        assert_select "button", text: "Withdraw response", count: 0
        post withdraw_form_response_path(@form, person(:a1))
        assert @form.response_for(person(:a1)).reload.complete?, "can't withdraw while an update is in progress"

        get results_form_path(@form)
        assert_redirected_to root_path, "students can't see everyone's results"
      end
      as(:pack_leader) do
        get results_form_path(@form)
        assert_select "tr#person_#{person(:a1).id} td", text: "Slim 1"
        get results_form_path(@form, version: "latest")
        assert_select "tr#person_#{person(:a1).id} td", text: /Slim 4/
      end
    end
  end

  test "after withdrawing, filling in again starts from the withdrawn answers" do
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Big John" })
    with_feature do
      as(:a1) do
        post withdraw_form_response_path(@form, person(:a1))
        assert @form.response_for(person(:a1)).withdrawn?
        get edit_form_response_path(@form, person(:a1))
        assert_select "select[name='form_response[answers][sandwich]'] option[selected]", text: "Big John"
        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "Big John" } }, submit: "1" }
        assert @form.response_for(person(:a1)).reload.complete?
      end
    end
  end

  test "people can't open responses they aren't allowed to see" do
    with_feature do
      as(:parent_a1) do
        get edit_form_response_path(@form, person(:a2))
        assert_redirected_to root_path
        patch form_response_path(@form, person(:a2)), params: { form_response: { answers: { sandwich: "Slim 1" } }, submit: "1" }
        get form_response_path(@form, person(:a2))
        assert_redirected_to root_path
      end
      assert_nil @form.response_for(person(:a2))
    end
  end

  test "closed forms only take late entries from leaders" do
    @form.update!(status: :closed)
    with_feature do
      as(:a1) do
        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "Slim 1" } }, submit: "1" }
      end
      assert_nil @form.response_for(person(:a1))

      as(:den_a_leader) do
        patch form_response_path(@form, person(:a1)), params: { form_response: { answers: { sandwich: "Slim 1" } }, submit: "1" }
      end
      assert @form.response_for(person(:a1)).active_submission.entered_late?
    end
  end

  test "the status page, CSV, and tally for a leader" do
    with_settings(feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      person(:a1).set_field_value(allergies, "peanut")
      respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })

      with_feature do
        as(:den_a_leader) do
          get form_path(@form)
          assert_response :success
          assert_select "a", text: /Complete \(1\)/
          assert_select "a", text: /Not started/

          get results_form_path(@form, format: :csv, field_ids: [ allergies.id ])
          assert_response :success
          csv = CSV.parse(response.body)
          assert_equal [ "Last name", "First name", "Status", "Version", "Form version", "Submitted by", "Submitted at", "Signed by", "Signed at", "Sandwich", "Food Allergies" ], csv.first
          a1_row = csv.detect { |row| row[1] == "A1" }
          assert_equal [ "Complete", "1", "1", "A1 World" ], a1_row[2..5]
          assert_equal [ "Slim 4", "peanut" ], a1_row[9..10]
          assert_nil csv.detect { |row| row[1] == "B1" }, "Den A's leader doesn't see Den B"

          get tally_form_path(@form)
          assert_select "td", text: "Slim 4"
        end
      end
    end
  end

  test "remind emails the people who can respond for those not complete" do
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    with_feature do
      as(:den_a_leader) do
        post remind_form_path(@form)
      end
      assert_empty @form.form_reminders, "Den A's leader doesn't manage the Pack form"

      as(:pack_leader) do
        assert_enqueued_jobs 7, only: SendEmailJob do
          post remind_form_path(@form)
        end
      end
    end
    # A2 and their parent, B1, and the leaders and assistant (audience members
    # who answer for themselves). Not A1, who is complete.
    reminder = @form.form_reminders.last
    assert_equal 7, reminder.recipient_count
    assert_equal person(:pack_leader), reminder.sent_by
  end

  test "the dashboard lists forms to complete for a person and their wards" do
    with_feature do
      as(:parent_a1) do
        get root_path
        assert_select ".card h2", text: "Forms to Complete"
        assert_select "a[href=?]", edit_form_response_path(@form, person(:a1))
      end
      respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
      as(:parent_a1) do
        get root_path
        assert_select ".card h2", text: "Forms to Complete", count: 0
      end
    end
  end

  test "preview explains access" do
    with_feature do
      as(:admin) do
        get preview_form_path(@form, preview: { viewer_id: person(:parent_a1).id, subject_id: person(:a1).id })
        assert_response :success
        assert_select "p", text: /Can fill it in as their guardian/
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
