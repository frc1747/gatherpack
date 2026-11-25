require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormSubmissionTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
    @form = create_world_form
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ], required: true)
    @remove = @form.form_questions.create!(kind: :input, label: "Please remove", data_type: :multi_select, choices: %w[ Lettuce Tomatoes Cheese ])
  end

  test "a submission without signatures becomes active when submitted" do
    submission = respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4", "please_remove" => [ "Lettuce", "" ] })

    assert submission.active?
    assert_equal "Slim 4", submission.answer(@sandwich)
    assert_equal [ "Lettuce" ], submission.answer(@remove)
    response = submission.form_response.reload
    assert response.complete?
    assert_equal submission, response.active_submission
    assert_equal person(:a1), submission.submitted_by
  end

  test "answers are checked against the choices" do
    response = @form.form_responses.create!(subject: person(:a1))
    submission = response.start_submission!(person(:a1))
    errors = submission.assign_answers({ "sandwich" => "Pizza" }, FormAccess.new(person(:a1), person(:a1), @form))
    assert_equal({ "sandwich" => "isn't one of the choices" }, errors)
  end

  test "required questions the respondent can answer must be answered" do
    response = @form.form_responses.create!(subject: person(:a1))
    submission = response.start_submission!(person(:a1))
    errors = submission.submit!(person(:a1), FormAccess.new(person(:a1), person(:a1), @form))
    assert_equal({ "sandwich" => "can't be blank" }, errors)
    assert submission.reload.draft?
  end

  test "an update starts from the active answers and replaces them only when submitted" do
    first = respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    response = first.form_response.reload

    draft = response.start_submission!(person(:parent_a1))
    assert draft.draft?
    assert_equal first, draft.based_on
    assert_equal "Slim 4", draft.answer(@sandwich)
    assert response.reload.complete?, "the active version stays in effect"
    assert response.update_in_progress?

    draft.assign_answers({ "sandwich" => "Big John" }, FormAccess.new(person(:parent_a1), person(:a1), @form))
    draft.save!
    assert_equal "Slim 4", response.reload.active_submission.answer(@sandwich)

    draft.submit!(person(:parent_a1), FormAccess.new(person(:parent_a1), person(:a1), @form))
    assert draft.reload.active?
    assert first.reload.superseded?
    response.reload
    assert_equal draft, response.active_submission
    assert_not response.update_in_progress?
    assert_equal [ 1, 2 ], response.form_submissions.map(&:number)
  end

  test "discarding the only draft leaves the response not started" do
    response = @form.form_responses.create!(subject: person(:a1))
    draft = response.start_submission!(person(:a1))
    assert response.reload.draft?

    draft.discard!(by: person(:a1))
    assert response.reload.not_started?
    assert_equal "not_started", FormReport.new(@form, viewer: person(:den_a_leader)).rows.detect { |row| row.person == person(:a1) }.status

    response.start_submission!(person(:a1))
    assert response.reload.draft?, "starting again is in progress"
  end

  test "a required question someone else answers leaves the submission waiting" do
    notes = add_choice(@form, "Leader check", %w[ OK ], required: true, read_permission: "family", write_permission: "leaders")
    submission = respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })
    assert submission.pending?
    assert submission.form_response.reload.waiting?

    leader = FormAccess.new(person(:den_a_leader), person(:a1), @form)
    submission.assign_answers({ "leader_check" => "OK" }, leader)
    assert submission.draft?, "changing a pending submission returns it to draft"
    submission.save!
    submission.submit!(person(:den_a_leader), leader)
    assert submission.reload.active?
    assert_equal "OK", submission.answer(notes)
  end

  test "withdrawing and discarding" do
    first = respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    response = first.form_response.reload
    draft = response.start_submission!(person(:a1))
    draft.discard!
    assert response.reload.complete?
    assert_not response.update_in_progress?

    first.reload.withdraw!
    response.reload
    assert response.withdrawn?
    assert_nil response.active_submission
  end

  test "updates profile answers are written when the submission becomes active" do
    with_settings(feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      person(:a1).set_field_value(allergies, "peanut")
      question = add_profile_question(@form, allergies, :update_profile)

      response = @form.form_responses.create!(subject: person(:a1))
      draft = response.start_submission!(person(:parent_a1))
      assert_equal "peanut", draft.answer(question), "starts from the profile"

      access = FormAccess.new(person(:parent_a1), person(:a1), @form)
      draft.assign_answers({ "sandwich" => "Slim 1", "food_allergies" => "peanut, shellfish" }, access)
      draft.save!
      assert_equal "peanut", person(:a1).reload.field_value(allergies), "an unsubmitted answer never changes the profile"

      draft.submit!(person(:parent_a1), access)
      assert draft.reload.active?
      assert_equal "peanut, shellfish", person(:a1).reload.field_value(allergies)
      assert_empty draft.profile_skipped
    end
  end

  test "filled-in-from-profile answers stay on the form" do
    with_settings(feature_person_fields: "true") do
      contact = create_world_field("Emergency Contact", read: "family", write: "family")
      person(:a1).set_field_value(contact, "Mom 555-0100")
      add_profile_question(@form, contact, :prefill)

      submission = respond(@form, :a1, as: :parent_a1, answers: { "sandwich" => "Slim 1", "emergency_contact" => "Grandma 555-0199" })
      assert_equal "Grandma 555-0199", submission.answers["emergency_contact"]
      assert_equal "Mom 555-0100", person(:a1).reload.field_value(contact)
    end
  end

  test "a profile write the submitter isn't allowed is skipped and recorded" do
    with_settings(feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      add_profile_question(@form, allergies, :update_profile)
      submission = respond(@form, :a1, as: :parent_a1, answers: { "sandwich" => "Slim 1", "food_allergies" => "none" })
      assert_equal "none", person(:a1).reload.field_value(allergies)

      # Guardianship ends before the next update activates.
      Relationship.where(parent: person(:parent_a1), child: person(:a1)).destroy_all
      allergies.update!(write_permission: "self_and_leaders", read_permission: "family")
      response = submission.form_response.reload
      draft = response.start_submission!(person(:a1))
      access = FormAccess.new(person(:a1), person(:a1), @form)
      draft.assign_answers({ "food_allergies" => "dairy" }, access)
      draft.save!
      draft.update!(submitted_by: person(:assistant))
      draft.send(:apply_to_profile!)
      assert_equal [ "food_allergies" ], draft.reload.profile_skipped
      assert_equal "none", person(:a1).reload.field_value(allergies)
    end
  end

  test "an unrelated required profile field doesn't block a profile update" do
    with_settings(feature_person_fields: "true") do
      create_world_field("Emergency Contact", read: "family", write: "family", required: true)
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      add_profile_question(@form, allergies, :update_profile)

      submission = respond(@form, :a1, as: :parent_a1, answers: { "sandwich" => "Slim 1", "food_allergies" => "dairy" })
      assert submission.active?
      assert_equal "dairy", person(:a1).reload.field_value(allergies)
      assert_empty submission.profile_skipped
    end
  end

  test "hooks run on submit, activation, and completion" do
    events = []
    %w[ form_submissions\ -\ submitted form_submissions\ -\ activated form_responses\ -\ completed form_responses\ -\ incomplete ].each do |event|
      Hook.create!(name: event, event: event, code: "Thread.current[:form_hook_events] << \"#{event}\"")
    end
    Thread.current[:form_hook_events] = events

    submission = respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })
    submission.withdraw!

    assert_equal [ "form_submissions - submitted", "form_submissions - activated", "form_responses - completed", "form_responses - incomplete" ], events
  ensure
    Thread.current[:form_hook_events] = nil
  end
end
