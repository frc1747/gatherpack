require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# A profile-backed question keeps a copy of the answer on each submission.
# That copy stays behind the person field's own read level: unlinking or
# removing the question doesn't open it up, and no other question can take
# over its stored answers.
class FormProfileAnswersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  NOTE = "Carries an inhaler"

  setup do
    host! "localhost"
    build_person_fields_world
  end

  # A Den A form with a question filled in from an admin-only field. A1
  # starting their response copies the value in, unseen.
  def with_admin_only_question
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      @notes = create_world_field("Medical notes", read: "admin", write: "admin")
      person(:a1).set_field_value(@notes, NOTE)
      @form = create_world_form("Trip", team: @den_a, include: [ @den_a ])
      @question = add_profile_question(@form, @notes, :prefill)
      add_choice(@form, "Bus seat", [ "Front", "Back" ])
      @submission = respond(@form, :a1, as: :a1, answers: { "bus_seat" => "Front" })
      assert_equal NOTE, @submission.answers[@question.key]
      yield
    end
  end

  test "an answered question stays linked to its profile field" do
    with_admin_only_question do
      as(:den_a_leader) do
        get form_response_path(@form, person(:a1))
        assert_response :success
        assert_not_includes response.body, NOTE

        patch form_question_path(@form, @question), params: { form_question: { person_field_id: "", read_permission: "" } }
        get form_response_path(@form, person(:a1))
        assert_not_includes response.body, NOTE
        assert_equal @notes, @question.reload.person_field, "the link can't change once the question has answers"
      end
    end
  end

  test "a removed profile-backed question's answer follows the field on the submission page" do
    with_admin_only_question do
      as(:den_a_leader) do
        delete form_question_path(@form, @question)
        get form_response_submission_path(@form, person(:a1), @submission)
        assert_response :success
        assert_not_includes response.body, NOTE
      end

      as(:admin) do
        get form_response_submission_path(@form, person(:a1), @submission)
        assert_includes response.body, NOTE, "someone who can read the field still sees it"
      end
    end
  end

  test "a removed question whose field is unknown isn't shown" do
    with_admin_only_question do
      @question.destroy!
      content = @submission.content.deep_dup
      content["questions"].detect { |snapshot| snapshot["key"] == @question.key }["person_field"] = "no_longer_here"
      @submission.update_column(:content, content)
      as(:admin) do
        get form_response_submission_path(@form, person(:a1), @submission)
        assert_response :success
        assert_not_includes response.body, NOTE
      end
    end
  end

  test "a removed form-only question's answer is still shown to leaders" do
    with_settings(feature_forms: "true") do
      form = create_world_form("Trip", team: @den_a, include: [ @den_a ])
      seat = add_choice(form, "Bus seat", [ "Front", "Back" ])
      submission = respond(form, :a1, as: :a1, answers: { "bus_seat" => "Front" })
      seat.destroy!
      as(:den_a_leader) do
        get form_response_submission_path(form, person(:a1), submission)
        assert_select "div", text: /Front\s+question since removed/
      end
    end
  end

  test "changing an answered question's kind and back doesn't unlink it" do
    with_admin_only_question do
      as(:den_a_leader) do
        patch form_question_path(@form, @question), params: { form_question: { kind: "heading" } }
        patch form_question_path(@form, @question), params: { form_question: { kind: "input" } }
        assert @question.reload.input?
        assert_equal @notes, @question.person_field
        get results_form_path(@form, format: :csv)
        assert_not_includes response.body, NOTE
      end

      @question.kind = "heading"
      assert_not @question.save
      assert_includes @question.errors[:kind], "can't be changed once the question has answers"
      assert_includes @question.errors[:person_field_id], "can't be changed once the question has answers"
    end
  end

  test "an answered acknowledgment can't become an input with another type" do
    with_settings(feature_forms: "true") do
      form = create_world_form("Trip", team: @den_a, include: [ @den_a ])
      rules = form.form_questions.create!(kind: :acknowledgment, label: "I read the rules")
      respond(form, :a1, as: :a1, answers: { rules.key => "1" })
      assert_not rules.update(kind: "input", data_type: "string")
      assert_includes rules.errors[:data_type], "can't be changed once the question has answers"
    end
  end

  test "a new question can't take the key of a removed question with answers" do
    with_admin_only_question do
      as(:den_a_leader) do
        delete form_question_path(@form, @question)
        post form_questions_path(@form), params: { form_question: { kind: "input", key: "medical_notes", label: "Notes", data_type: "string" } }
        assert_response :unprocessable_entity
        assert_select ".invalid-feedback", text: /was used by a removed question/
        get form_response_path(@form, person(:a1))
        assert_not_includes response.body, NOTE

        post form_questions_path(@form), params: { form_question: { kind: "input", label: "Medical notes", data_type: "string" } }
        assert_redirected_to edit_form_path(@form, tab: "questions")
        assert @form.form_questions.exists?(key: "medical_notes_2"), "a generated key skips keys earlier answers use"
      end
    end
  end

  test "an answer recorded under a profile field isn't shown for a question unlinked before the lock" do
    with_admin_only_question do
      @question.update_columns(person_field_id: nil, profile_mode: nil, data_type: "string")
      as(:den_a_leader) do
        [ form_response_path(@form, person(:a1)), results_form_path(@form), results_form_path(@form, format: :csv),
          print_list_forms_path(form_id: @form.id, columns_for: @form.id, question_ids: [ @question.id ]) ].each do |path|
          get path
          assert_response :success
          assert_not_includes response.body, NOTE, path
        end
        get edit_form_response_path(@form, person(:a1))
        assert_not_includes response.body, NOTE, "a new version doesn't start from it"
      end
      assert_nil FormReport.new(@form, viewer: person(:admin)).answer(FormReport.new(@form, viewer: person(:admin)).rows.detect { |row| row.person == person(:a1) }, @question)
    end
  end

  test "a guardian's response completes with a required question filled in from a field only leaders see" do
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      shirt = create_world_field("Shirt size", read: "self_and_leaders", write: "self_and_leaders")
      person(:a1).set_field_value(shirt, "M")
      form = create_world_form("Trip", team: @den_a, include: [ @den_a ])
      add_profile_question(form, shirt, :prefill, required: true)
      add_choice(form, "Bus seat", [ "Front", "Back" ])

      as(:parent_a1) do
        patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { bus_seat: "Back" } } }
      end
      assert form.response_for(person(:a1)).complete?
      assert_equal "M", form.response_for(person(:a1)).active_submission.answers["shirt_size"]
    end
  end

  test "a manager builds a question from a field they can read, and it fills in for respondents and guardians" do
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      person(:a1).set_field_value(allergies, "Peanuts")
      form = create_world_form("Trip", team: @den_a, include: [ @den_a ])

      as(:den_a_leader) do
        post form_questions_path(form), params: { form_question: { kind: "input", label: "Allergies", person_field_id: allergies.id, profile_mode: "prefill" } }
        assert_redirected_to edit_form_path(form, tab: "questions")
      end
      question = form.form_questions.find_by!(key: "allergies")

      as(:a1) do
        get edit_form_response_path(form, person(:a1))
        assert_select "input[name=?][value=?]", "form_response[answers][allergies]", "Peanuts"
      end
      as(:parent_a1) do
        get edit_form_response_path(form, person(:a1))
        assert_select "input[name=?][value=?]", "form_response[answers][allergies]", "Peanuts"
        patch form_response_path(form, person(:a1)), params: { submit: "1", form_response: { answers: { allergies: "Peanuts" } } }
      end
      assert_equal "Peanuts", form.response_for(person(:a1)).active_submission.answers[question.key]
    end
  end

  test "a question's profile field can change until someone answers it" do
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      shirt = create_world_field("Shirt size", read: "family", write: "family")
      form = create_world_form("Trip", team: @den_a, include: [ @den_a ])
      question = add_profile_question(form, allergies, :prefill)

      as(:den_a_leader) do
        patch form_question_path(form, question), params: { form_question: { person_field_id: shirt.id } }
        assert_equal shirt, question.reload.person_field
        patch form_question_path(form, question), params: { form_question: { person_field_id: "" } }
        assert_nil question.reload.person_field
      end
    end
  end

  private

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
