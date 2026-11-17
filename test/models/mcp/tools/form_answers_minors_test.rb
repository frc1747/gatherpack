require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"

class Mcp::Tools::FormAnswersMinorsTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld

  ADULT_BIRTHDAY = Date.new(1990, 5, 6)

  CONTACT_LABELS = [ "Linked email", "Linked phone", "Linked address", "Linked birthday", "Own phone", "Own email", "Emergency phone" ].freeze
  OTHER_LABELS = [ "Home", "Trip date", "Pick", "Backup number", "Coming" ].freeze

  # Values only a contact question holds, none of them on anyone's profile.
  CONTACT_ANSWERS = {
    "linked_email" => "linked@example.com", "linked_phone" => "555-0101", "linked_address" => "1 Main St", "linked_birthday" => "2010-05-06",
    "own_phone" => "555-0102", "own_email" => "own@example.com", "emergency_phone" => "555-0103"
  }.freeze
  OTHER_ANSWERS = { "home" => "2 Side St", "trip_date" => "2026-12-01", "pick" => "a", "backup_number" => "555-0104", "coming" => "Yes" }.freeze

  setup do
    build_mcp_world
    build_mcp_forms_world
    PersonField.ensure_system_fields!

    person(:ward).update!(birthday: 16.years.ago.to_date)
    person(:alpha_member).update!(birthday: ADULT_BIRTHDAY)

    @contacts = create_world_form("Contacts", @alpha)
    { "linked_email" => [ "Linked email", "user.email" ], "linked_phone" => [ "Linked phone", "phone_number" ],
      "linked_address" => [ "Linked address", "address" ], "linked_birthday" => [ "Linked birthday", "birthday" ] }.each do |key, (label, source)|
      @contacts.form_questions.create!(kind: :input, key: key, label: label, person_field: PersonField.system_field(source), profile_mode: :prefill)
    end
    @contacts.form_questions.create!(kind: :input, key: "own_phone", label: "Own phone", data_type: :phone)
    @contacts.form_questions.create!(kind: :input, key: "own_email", label: "Own email", data_type: :email)
    emergency = PersonField.create!(name: "Emergency", data_type: :phone, read_permission: "everyone", write_permission: "everyone")
    @contacts.form_questions.create!(kind: :input, key: "emergency_phone", label: "Emergency phone", person_field: emergency, profile_mode: :prefill)

    # Free text and a plain date can't be judged. A custom field keyed like a
    # withheld value isn't the built-in one.
    @contacts.form_questions.create!(kind: :input, key: "home", label: "Home", data_type: :string)
    @contacts.form_questions.create!(kind: :input, key: "trip_date", label: "Trip date", data_type: :date)
    @contacts.form_questions.create!(kind: :input, key: "pick", label: "Pick", data_type: :select, choices: %w[ a b ])
    lookalike = PersonField.create!(key: "phone_number", name: "Backup", data_type: :string, read_permission: "everyone", write_permission: "everyone")
    @contacts.form_questions.create!(kind: :input, key: "backup_number", label: "Backup number", person_field: lookalike, profile_mode: :prefill)
    @contacts.form_questions.create!(kind: :intent, key: "coming", label: "Coming")
    @contacts.form_questions.reset

    answer_all(:ward, as: :guardian)
    answer_all(:alpha_member, as: :alpha_member)
  end

  def answer_all(subject, as:, form: @contacts)
    respond_to_form(form, subject, as: as, answers: CONTACT_ANSWERS.merge(OTHER_ANSWERS))
  end

  def answers_for(viewer, name, form: @contacts)
    result = call_tool("form_answers", user: user(viewer), form_id: form.neat_id)
    item = result.value["items"].find { |entry| entry["person"]["name"] == name }
    assert item, "#{name} should be listed for #{viewer}"
    item["answers"]
  end

  def assert_contact_answers_left_out(answers)
    assert_equal OTHER_LABELS.sort, answers.map { |answer| answer["label"] }.sort
    assert_equal OTHER_ANSWERS.values.sort, answers.map { |answer| answer["answer"].to_s }.sort
  end

  def assert_every_answer_returned(answers)
    assert_equal (CONTACT_LABELS + OTHER_LABELS).sort, answers.map { |answer| answer["label"] }.sort
    assert_equal CONTACT_ANSWERS.merge(OTHER_ANSWERS).values.sort, answers.map { |answer| answer["answer"].to_s }.sort
  end

  test "the withheld answers are really stored for a minor" do
    stored = @contacts.response_for(person(:ward)).active_submission.answers

    assert_equal CONTACT_ANSWERS, stored.slice(*CONTACT_ANSWERS.keys)
  end

  test "an admin and a form manager get no contact answers for a 16-year-old, and the others remain" do
    %i[ admin alpha_manager ].each { |viewer| assert_contact_answers_left_out(answers_for(viewer, "Ward World")) }
  end

  test "an admin and a form manager get no contact answers for someone with no birthday on file" do
    person(:ward).update!(birthday: nil)

    %i[ admin alpha_manager ].each { |viewer| assert_contact_answers_left_out(answers_for(viewer, "Ward World")) }
  end

  test "an admin and a form manager get every answer for an adult" do
    %i[ admin alpha_manager ].each { |viewer| assert_every_answer_returned(answers_for(viewer, "AlphaMember World")) }
  end

  test "an adult and a minor on one form are each handled alone, in either order" do
    answers_by_name = call_tool("form_answers", user: user(:admin), form_id: @contacts.neat_id).value["items"]
      .to_h { |item| [ item["person"]["name"], item["answers"] ] }

    assert_every_answer_returned(answers_by_name.fetch("AlphaMember World"))
    assert_contact_answers_left_out(answers_by_name.fetch("Ward World"))

    person(:alpha_member).update!(birthday: 16.years.ago.to_date)
    person(:ward).update!(birthday: ADULT_BIRTHDAY)

    assert_contact_answers_left_out(answers_for(:admin, "AlphaMember World"))
    assert_every_answer_returned(answers_for(:admin, "Ward World"))
  end

  test "the response's subject is judged, not who filled it in" do
    person(:guardian).update!(birthday: ADULT_BIRTHDAY)
    assert_contact_answers_left_out(answers_for(:admin, "Ward World"))

    person(:alpha_manager).update!(birthday: nil)
    submission = answer_all(:alpha_member, as: :alpha_manager)
    assert_equal person(:alpha_manager), submission.submitted_by
    assert_every_answer_returned(answers_for(:admin, "AlphaMember World"))
  end

  test "a guardian's own response is judged on the guardian's own age" do
    @contacts.form_audience_rules.create!(effect: :include, target_type: :person, person: person(:guardian))
    @contacts.form_audience_rules.reset
    answer_all(:guardian, as: :guardian)

    person(:guardian).update!(birthday: ADULT_BIRTHDAY)
    assert_every_answer_returned(answers_for(:admin, "Guardian World"))
    assert_contact_answers_left_out(answers_for(:admin, "Ward World"))

    person(:guardian).update!(birthday: 16.years.ago.to_date)
    assert_contact_answers_left_out(answers_for(:admin, "Guardian World"))
  end

  test "person_id gives the same answers" do
    result = call_tool("form_answers", user: user(:admin), form_id: @contacts.neat_id, person_id: person(:ward).neat_id)

    assert_contact_answers_left_out(result.value["items"].first["answers"])
  end

  test "a linked question is left out by its source alone, whatever its field's type" do
    PersonField.where(system_source: %w[ user.email phone_number ]).find_each { |field| field.update_columns(data_type: PersonField.data_types[:string]) }

    assert_contact_answers_left_out(answers_for(:admin, "Ward World"))
  end

  test "a question that updates the profile is left out like one that only prefills" do
    question = @contacts.form_questions.find_by!(key: "linked_phone")
    question.update!(profile_mode: :update_profile)

    assert_contact_answers_left_out(answers_for(:admin, "Ward World"))
  end

  test "a contact question the viewer can't read is left out, not shown as hidden" do
    question = @contacts.form_questions.find_by!(key: "own_phone")
    question.update!(read_permission: "admin")

    assert_nil answers_for(:alpha_manager, "Ward World").find { |answer| answer["label"] == "Own phone" }
    hidden = answers_for(:alpha_manager, "AlphaMember World").find { |answer| answer["label"] == "Own phone" }
    assert_not hidden["readable"]
    assert_nil hidden["answer"]
  end

  test "the result gives no reason for what it leaves out, and the description explains it" do
    result = call_tool("form_answers", user: user(:admin), form_id: @contacts.neat_id, person_id: person(:ward).neat_id)

    assert_no_match(/minor|under 18|birthday on file|withheld/i, result.value.to_json)
    assert_equal %w[ person submission answers ].sort, result.value["items"].first.keys.sort
    description = Mcp::Tools::FormAnswers.description
    assert_includes description, "Questions linked to the built-in email, phone, address or birthday fields, questions of phone or email type, and questions that were either of those earlier are left out"
    assert_includes description, "under 18 or with no birthday on file"
    assert_includes description, "Other answers may still hold the same details"
  end

  test "form_status and list_forms carry no answer values, for a minor or anyone else" do
    %i[ admin alpha_manager ].each do |viewer|
      status = call_tool("form_status", user: user(viewer), form_id: @contacts.neat_id).value.to_json
      forms = call_tool("list_forms", user: user(viewer), status: "all", limit: 100).value.to_json

      CONTACT_ANSWERS.each_value do |value|
        assert_not_includes status, value
        assert_not_includes forms, value
      end
    end
  end
end
