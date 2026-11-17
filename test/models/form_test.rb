require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
  end

  test "keys are generated from the title and can't change" do
    form = create_world_form("2026-27 Meal Choices")
    assert_equal "meal_choices", form.key
    assert_equal "meal_choices_2", create_world_form("Meal Choices!").key

    form.key = "other"
    assert_not form.valid?
  end

  test "the schedule opens and closes forms" do
    to_open = create_world_form("Opens", status: :draft, opens_at: 1.minute.ago, closes_at: 1.day.from_now)
    later = create_world_form("Later", status: :draft, opens_at: 1.day.from_now)
    to_close = create_world_form("Closes", status: :open, closes_at: 1.minute.ago)

    with_settings(feature_forms: "true") { FormScheduleJob.perform_now }

    assert to_open.reload.open?
    assert later.reload.draft?
    assert to_close.reload.closed?
  end

  test "the schedule waits while forms are off" do
    to_open = create_world_form("Opens", status: :draft, opens_at: 1.minute.ago)
    to_close = create_world_form("Closes", status: :open, closes_at: 1.minute.ago)

    FormScheduleJob.perform_now

    assert to_open.reload.draft?
    assert to_close.reload.open?
  end

  test "duplicating copies settings and questions, not responses" do
    form = create_world_form
    add_choice(form, "Sandwich", [ "Slim 1" ])
    respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })

    copy = form.duplicate!(title: "Meal Choices 2028")
    assert copy.draft?
    assert_equal "meal_choices_2028", copy.key
    assert_equal [ "sandwich" ], copy.form_questions.map(&:key)
    assert_equal [ "Slim 1" ], copy.form_questions.first.choice_list
    assert_empty copy.form_responses
  end

  test "questions need choices and valid profile links" do
    form = create_world_form
    assert_not form.form_questions.build(kind: :input, label: "Pick", data_type: :select).valid?

    with_settings(feature_person_fields: "true") do
      email = PersonField.system_field("user.email") || PersonField.ensure_system_fields! && PersonField.system_field("user.email")
      question = form.form_questions.build(kind: :input, label: "Email", person_field: email, profile_mode: :update_profile)
      assert_not question.valid?
      assert question.errors.key?(:person_field)
    end
  end

  test "the report reads active answers per viewer and tallies them" do
    form = create_world_form(read: "family", respond: "family")
    sandwich = add_choice(form, "Sandwich", [ "Slim 1", "Slim 4" ])
    respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 4" })
    respond(form, :b1, as: :b1, answers: { "sandwich" => "Slim 1" })
    # An update in progress doesn't count until submitted.
    form.response_for(person(:b1)).start_submission!(person(:b1)).update!(answers: { "sandwich" => "Slim 4" })

    pack = FormReport.new(form, viewer: person(:pack_leader))
    assert_equal({ "Slim 1" => 1, "Slim 4" => 2, nil => 4 }, pack.tally(sandwich), "the leaders and assistant in the audience have no answer")
    latest = FormReport.new(form, viewer: person(:pack_leader), version: :latest)
    assert_equal 3, latest.tally(sandwich)["Slim 4"]

    parent = FormReport.new(form, viewer: person(:parent_a1))
    assert_equal [ person(:a1) ], parent.rows.map(&:person)
    assert_equal "Slim 4", parent.answer(parent.rows.first, "sandwich")

    den_b = FormReport.new(form, viewer: person(:den_b_leader))
    assert_equal({ "Slim 1" => 1, "Slim 4" => 0, nil => 1 }, den_b.tally(sandwich))
  end

  test "the report flags profile changes since an update_profile answer was submitted" do
    with_settings(feature_person_fields: "true") do
      allergies = create_world_field("Food Allergies", read: "family", write: "family")
      form = create_world_form
      add_profile_question(form, allergies, :update_profile)
      respond(form, :a1, as: :parent_a1, answers: { "food_allergies" => "peanut" })

      report = FormReport.new(form, viewer: person(:den_a_leader))
      row = report.rows.detect { |candidate| candidate.person == person(:a1) }
      assert_not report.changed_since_signed?(row, "food_allergies")

      person(:a1).set_field_value(allergies, "peanut, dairy")
      report = FormReport.new(form, viewer: person(:den_a_leader))
      row = report.rows.detect { |candidate| candidate.person == person(:a1) }
      assert report.changed_since_signed?(row, "food_allergies")
      assert_equal "peanut, dairy", report.profile(row, "food_allergies")
    end
  end
end
