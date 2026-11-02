require "test_helper"
require_relative "../support/mcp_world"
require_relative "../support/mcp_forms_world"

# Answers are stored by key and stay active when a question is edited, so each
# edit here, made as the form's manager, reads an old answer through a new
# definition. A minor's contact answer must stay out, and an adult's stays in.
class McpFormAnswersQuestionEditsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpFormsWorld

  ANSWERS = {
    "linked_email" => "linked@example.com", "linked_phone" => "555-0101", "linked_address" => "1 Main St", "linked_birthday" => "2010-05-06",
    "own_phone" => "555-0102", "pick" => "kept"
  }.freeze

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_forms_world
    PersonField.ensure_system_fields!

    person(:ward).update!(birthday: 16.years.ago.to_date)
    person(:alpha_member).update!(birthday: Date.new(1990, 5, 6))

    @form = create_world_form("Contacts", @alpha)
    { "linked_email" => "user.email", "linked_phone" => "phone_number", "linked_address" => "address", "linked_birthday" => "birthday" }.each do |key, source|
      @form.form_questions.create!(kind: :input, key: key, label: key.humanize, person_field: PersonField.system_field(source), profile_mode: :prefill)
    end
    @form.form_questions.create!(kind: :input, key: "own_phone", label: "Own phone", data_type: :phone)
    @form.form_questions.create!(kind: :input, key: "pick", label: "Pick", data_type: :string)
    @form.form_questions.reset
    @custom_text = PersonField.create!(name: "Custom text", data_type: :string, read_permission: "everyone", write_permission: "everyone")

    respond_to_form(@form, :ward, as: :guardian, answers: ANSWERS)
    respond_to_form(@form, :alpha_member, as: :alpha_member, answers: ANSWERS)
    sign_in user(:alpha_manager)
  end

  def question(key)
    @form.form_questions.find_by!(key: key)
  end

  def edit_question(key, **attributes)
    patch form_question_path(@form, question(key)), params: { form_question: attributes }
    assert_response :see_other
  end

  def answers_for(name)
    result = call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
    result.value["items"].find { |item| item["person"]["name"] == name }["answers"].to_h { |answer| [ answer["question_id"], answer["answer"] ] }
  end

  # The edit changed the question, the minor's response still holds the value and
  # stays in effect, and only that answer is affected.
  def assert_left_out_for_the_minor_only(key)
    question = question(key)
    value = ANSWERS.fetch(key)
    response = @form.response_for(person(:ward))
    assert_equal value, response.active_submission.answers[key]
    assert_equal "complete", response.status

    ward = answers_for("Ward World")
    assert_not_includes ward.keys, question.neat_id
    assert_not_includes ward.values, value
    assert_includes ward.values, "kept"
    assert_equal value, answers_for("AlphaMember World")[question.neat_id].to_s
  end

  %w[ linked_email linked_phone linked_address linked_birthday ].each do |key|
    test "unlinking #{key} after it was answered keeps it out for a minor" do
      edit_question(key, person_field_id: "")

      assert_nil question(key).person_field_id
      assert_left_out_for_the_minor_only(key)
    end
  end

  test "linking a typed phone question to a custom text field keeps it out for a minor" do
    edit_question("own_phone", person_field_id: @custom_text.id, profile_mode: "prefill")

    assert_equal @custom_text, question("own_phone").person_field
    assert_left_out_for_the_minor_only("own_phone")
  end

  test "moving a built-in phone link to a custom text field keeps it out for a minor" do
    edit_question("linked_phone", person_field_id: @custom_text.id, profile_mode: "prefill")

    assert_equal @custom_text, question("linked_phone").person_field
    assert_left_out_for_the_minor_only("linked_phone")
  end

  test "removing a typed phone question and adding a text one with the same key keeps it out for a minor" do
    delete form_question_path(@form, question("own_phone"))
    assert_response :see_other
    post form_questions_path(@form), params: { form_question: { kind: "input", label: "Own phone", data_type: "string" } }
    assert_response :redirect

    assert question("own_phone").type_string?
    assert_left_out_for_the_minor_only("own_phone")
  end

  test "an archived built-in field in a snapshot still counts" do
    edit_question("linked_address", person_field_id: "")
    PersonField.system_field("address").update!(archived_at: Time.current)

    assert_left_out_for_the_minor_only("linked_address")
  end

  test "a submission without a snapshot is judged as the question is now" do
    @form.response_for(person(:ward)).active_submission.update_columns(content: {})

    ward = answers_for("Ward World")
    assert_not_includes ward.values, "555-0102"
    assert_not_includes ward.values, "555-0101"
    assert_includes ward.values, "kept"
  end

  test "the snapshots' fields are loaded once, however many minors answered" do
    edit_question("own_phone", person_field_id: "")
    person(:alpha_member).update!(birthday: 16.years.ago.to_date)
    loads = 0
    counter = ->(*, payload) { loads += 1 if payload[:sql].include?("system_source") && payload[:sql].include?("\"key\"") }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      call_tool("form_answers", user: user(:alpha_manager), form_id: @form.neat_id)
    end

    assert_equal 1, loads
  end
end
