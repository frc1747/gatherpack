require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Runs only where people can be merged (GatherPack::PersonMerge is loaded).
class FormsPersonMergeTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  COLUMNS = %w[
    forms.created_by_id form_responses.subject_id form_submissions.created_by_id form_submissions.submitted_by_id
    form_signatures.signer_id form_signatures.revoked_by_id form_audience_rules.person_id form_reminders.sent_by_id
  ].freeze

  setup do
    skip "people can't be merged here" unless defined?(GatherPack::PersonMerge)
  end

  test "every column forms adds is covered by a merge" do
    uncovered = COLUMNS.reject { |name| GatherPack::PersonMerge.covers?(*name.split(".")) }

    assert_empty uncovered
  end

  test "the more complete response stays, with its versions" do
    build_person_fields_world
    form = create_world_form
    add_choice(form, "Sandwich", [ "Slim 1", "Slim 4" ])
    respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" }, submit: false)
    submitted = respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 4" })

    merge(keep: person(:a1), drop: person(:a2))

    response = FormResponse.find_by!(form: form, subject: person(:a1))
    assert response.complete?
    assert_equal submitted, response.active_submission
    assert_equal [ submitted ], response.form_submissions.to_a
    assert_equal 1, form.form_responses.count
  end

  test "the kept person's response stays when both are as complete" do
    build_person_fields_world
    form = create_world_form
    add_choice(form, "Sandwich", [ "Slim 1", "Slim 4" ])
    kept = respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })
    respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 4" })

    merge(keep: person(:a1), drop: person(:a2))

    response = FormResponse.find_by!(form: form, subject: person(:a1))
    assert_equal kept, response.active_submission
    assert_equal 1, FormSubmission.where(form_response: form.form_responses).count
  end

  test "a response that moves over is checked against the kept person's profile" do
    with_settings(feature_person_fields: "true") do
      build_person_fields_world
      form = create_world_form
      shirt = create_world_field("Shirt Size", read: "family", write: "family")
      add_profile_question(form, shirt, :update_profile)
      form.update!(reconfirm_on_profile_change: true)
      person(:a1).set_field_value(shirt, "L")
      respond(form, :a1, as: :a1, answers: { "shirt_size" => "L" }, submit: false)
      respond(form, :a2, as: :a2, answers: { "shirt_size" => "M" })

      merge(keep: person(:a1), drop: person(:a2))

      response = FormResponse.find_by!(form: form, subject: person(:a1))
      assert_equal "M", response.active_submission.answer(form.form_questions.first)
      assert response.needs_reconfirmation?
      assert_equal :profile, response.reconfirmation_reason
    end
  end

  test "a hook that fails while the merged response is re-checked doesn't fail the merge" do
    with_settings(feature_person_fields: "true") do
      build_person_fields_world
      form = create_world_form
      shirt = create_world_field("Shirt Size", read: "family", write: "family")
      add_profile_question(form, shirt, :update_profile)
      form.update!(reconfirm_on_profile_change: true)
      person(:a1).set_field_value(shirt, "L")
      respond(form, :a1, as: :a1, answers: { "shirt_size" => "L" }, submit: false)
      respond(form, :a2, as: :a2, answers: { "shirt_size" => "M" })
      Hook.create!(name: "Fails", event: "form_responses - incomplete", code: "raise 'hook failed'")

      merge(keep: person(:a1), drop: person(:a2))

      assert_not Person.exists?(person(:a2).id)
      assert FormResponse.find_by!(form: form, subject: person(:a1)).needs_reconfirmation?
    end
  end

  test "the completion badge of a response that moves over isn't granted twice" do
    build_person_fields_world
    badge = create_world_badge("Meal Choices Done")
    form = create_world_form(completion_badge: badge)
    add_choice(form, "Sandwich", [ "Slim 1", "Slim 4" ])
    respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" }, submit: false)
    respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 4" })
    assert BadgeAssignment.exists?(badge: badge, person: person(:a2))

    merge(keep: person(:a1), drop: person(:a2))

    assert FormResponse.find_by!(form: form, subject: person(:a1)).complete?
    assert_equal 1, BadgeAssignment.where(badge: badge, person: person(:a1)).count
  end

  test "a response that moves over is checked once the profile has moved too" do
    skip "profile values aren't merged here" unless GatherPack::PersonMerge.covers?(:person_field_values, :person_id)

    with_settings(feature_person_fields: "true") do
      build_person_fields_world
      form = create_world_form
      shirt = create_world_field("Shirt Size", read: "family", write: "family")
      add_profile_question(form, shirt, :update_profile)
      form.update!(reconfirm_on_profile_change: true)
      respond(form, :a1, as: :a1, answers: {}, submit: false)
      respond(form, :a2, as: :a2, answers: { "shirt_size" => "M" })

      merge(keep: person(:a1), drop: person(:a2))

      assert_equal "M", Person.find(person(:a1).id).field_value(shirt)
      response = FormResponse.find_by!(form: form, subject: person(:a1))
      assert response.complete?
      assert_nil response.reconfirmation_reason
    end
  end

  test "the preview names the forms both people answered" do
    build_person_fields_world
    form = create_world_form
    other = create_world_form("Ride Home")
    [ :a1, :a2 ].each { |name| form.form_responses.create!(subject: person(name)) }
    other.form_responses.create!(subject: person(:a2))

    assert_equal "Both people have a response to Meal Choices. The more complete one stays; the other is removed.",
      FormResponseMerge.both_answered(person(:a2).id, person(:a1).id)
    assert_nil FormResponseMerge.both_answered(person(:b1).id, person(:a1).id)
  end

  private

  def merge(keep:, drop:)
    admin = User.create!(email: "forms-merge-admin@example.com", password: "Password1!", admin: true)
    assert PersonMerger.new(keep_nid: keep.neat_id, drop_nid: drop.neat_id, keep_login: "keep").merge(actor: admin)
  end
end
