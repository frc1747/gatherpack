require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"
require_relative "../../../support/mcp_form_responses_world"

class Mcp::Tools::GetFormTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
  end

  def get_form(viewer, form = @consent_form, subject = nil)
    arguments = { form_id: form.neat_id }
    arguments[:person_id] = person(subject).neat_id if subject
    call_tool("get_form", user: user(viewer), **arguments)
  end

  def labels(result)
    result.value["questions"].map { |question| question["label"] }
  end

  test "an admin and a team manager get the questions in order, with type, options and required" do
    %i[ admin alpha_manager ].each do |viewer|
      result = get_form(viewer)

      assert_nil result.error
      assert_equal [ "Choice", "Comment", "Agree", "Own phone", "Size", "Parent consent" ], labels(result)
      choice = result.value["questions"].first
      assert_equal [ @choice.neat_id, "input", "select", %w[ Red Blue ], true ], choice.values_at("id", "kind", "type", "options", "required")
      assert_nil result.value["response"]
    end
  end

  test "a question linked to a person field takes its type from the field and says it saves to the profile" do
    size = get_form(:admin).value["questions"].find { |question| question["label"] == "Size" }

    assert_equal "string", size["type"]
    assert_equal true, size["saves_to_profile"]
  end

  test "a signature question says who signs, and has no answer type" do
    signature = get_form(:admin).value["questions"].last

    assert_equal "signature", signature["kind"]
    assert_nil signature["type"]
    assert_includes signature["signer"], "guardian"
    assert_equal "I give permission.", signature["body"]
  end

  test "a member gets the form through their own response, not without one" do
    assert_equal "Not allowed", get_form(:alpha_member).error

    result = get_form(:alpha_member, @consent_form, :alpha_member)
    assert_nil result.error
    assert_includes labels(result), "Choice"
    assert_equal "not_started", result.value.dig("response", "status")
    assert_equal true, result.value.dig("response", "can_update")
  end

  test "a guardian gets the form through their ward's response" do
    assert_nil get_form(:guardian, @consent_form, :ward).error
    assert_equal "Not allowed", get_form(:guardian).error
  end

  test "a plain member on another team gets Not found" do
    assert_equal "Not found", get_form(:beta_member).error
    assert_equal "Not found", get_form(:beta_member, @consent_form, :alpha_member).error
    assert_equal "Not found", get_form(:beta_member, @consent_form, :beta_member).error
  end

  test "a read grant holder sees the form though the person is outside their teams" do
    assert_nil get_form(:coordinator, @lunch).error
    assert_nil get_form(:coordinator, @lunch, :alpha_member).error
  end

  test "a wrong ID is Not found" do
    assert_equal "Not found", call_tool("get_form", user: user(:admin), form_id: "frm_nope").error
    assert_equal "Not found", call_tool("get_form", user: user(:admin), form_id: person(:ward).neat_id).error
    assert_equal "Not found", call_tool("get_form", user: user(:admin), form_id: @lunch.neat_id, person_id: "per_nope").error
  end

  test "with a person, only the questions that person's viewer may read" do
    assert_not_includes labels(get_form(:coordinator, @lunch, :alpha_member)), "Allergies"
    assert_not_includes labels(get_form(:guardian, @lunch, :ward)), "Notes"

    assert_equal %w[ Sandwich Notes Allergies ], labels(get_form(:alpha_member, @lunch, :alpha_member))
  end

  test "states follow the response through draft, waiting and complete" do
    assert_equal "not_started", get_form(:admin, @consent_form, :alpha_member).value.dig("response", "status")

    save_answers(:alpha_member, :alpha_member, { @comment => "hi" })
    assert_equal "draft", get_form(:admin, @consent_form, :alpha_member).value.dig("response", "status")

    save_answers(:alpha_member, :alpha_member, { @choice => "Red" }, submit: true)
    waiting = get_form(:alpha_member, @consent_form, :alpha_member).value
    assert_equal "waiting", waiting.dig("response", "status")
    assert_equal true, waiting.dig("response", "can_sign")
    assert_match(/Parent consent/, waiting.dig("response", "waiting_for").first)
    assert_equal true, waiting["questions"].last["can_sign"]
    assert_equal false, waiting["questions"].last["signed"]

    call_tool("sign_form_response", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id,
      question_id: @signature.neat_id, typed_name: "AlphaMember World")
    complete = get_form(:alpha_member, @consent_form, :alpha_member).value
    assert_equal "complete", complete.dig("response", "status")
    assert_equal true, complete["questions"].last["signed"]
    assert_equal false, complete.dig("response", "can_sign")
    assert_equal true, complete.dig("response", "can_withdraw")
  end

  test "someone the form no longer asks shows as not asked" do
    response = get_form(:admin, @mixed, :beta_member).value["response"]

    assert_equal false, response["asked"]
    assert_equal "complete", response["status"]
  end

  def answers(result)
    result.value["questions"].select { |question| question.key?("answer") }.to_h { |question| [ question["label"], question["answer"] ] }
  end

  test "with a person, the answers the viewer may read, and only on what can be answered" do
    assert_equal({ "Sandwich" => "Slim 4", "Notes" => "no onions", "Allergies" => "peanut" }, answers(get_form(:alpha_member, @lunch, :alpha_member)))

    consent = get_form(:alpha_member, @consent_form, :alpha_member)
    assert_equal [ nil ], answers(consent).values.uniq
    assert_not consent.value["questions"].last.key?("answer")
  end

  test "a question the viewer can't read keeps its answer out" do
    coordinator = get_form(:coordinator, @lunch, :alpha_member)
    assert_equal "Slim 4", answers(coordinator)["Sandwich"]
    assert_not_includes coordinator.value.to_json, "peanut"

    guardian = get_form(:guardian, @lunch, :ward)
    assert_equal({ "Sandwich" => "Big John" }, answers(guardian))
  end

  test "without a person there are no answers" do
    result = get_form(:admin, @lunch)

    assert_empty answers(result)
    assert_not_includes result.value.to_json, "no onions"
  end

  test "a signer reads what they're asked to sign" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red", "comment" => "for the trip" })

    result = get_form(:guardian, @consent_form, :ward)

    assert_equal true, result.value.dig("response", "can_sign")
    assert_equal "Red", answers(result)["Choice"]
    assert_equal "for the trip", answers(result)["Comment"]
  end

  test "an unsubmitted update's answers show over those in effect" do
    plain_form
    respond_to_form(plain_form, :alpha_member, as: :alpha_member, answers: { "pick" => "first" })
    assert_equal "first", answers(get_form(:alpha_member, plain_form, :alpha_member))["Pick"]

    save_answers(:alpha_member, :alpha_member, { @plain_pick => "second" }, form: plain_form)

    result = get_form(:alpha_member, plain_form, :alpha_member)
    assert_equal "second", answers(result)["Pick"]
    assert_equal true, result.value.dig("response", "update_in_progress")
  end

  test "a withdrawn response has no answers to show" do
    respond_to_form(plain_form, :alpha_member, as: :alpha_member, answers: { "pick" => "first" })
    call_tool("withdraw_form_response", user: user(:alpha_member), form_id: plain_form.neat_id, person_id: person(:alpha_member).neat_id)

    assert_equal({ "Pick" => nil }, answers(get_form(:alpha_member, plain_form, :alpha_member)))
  end

  test "a date answer comes as YYYY-MM-DD and a yes/no as true" do
    form = create_world_form("Typed", @alpha)
    form.form_questions.create!(kind: :input, label: "Day", data_type: :date)
    form.form_questions.create!(kind: :acknowledgment, label: "Tick")
    form.form_questions.reset
    respond_to_form(form, :alpha_member, as: :alpha_member, answers: { "day" => "2026-03-04", "tick" => "1" })

    assert_equal({ "Day" => "2026-03-04", "Tick" => true }, answers(get_form(:alpha_member, form, :alpha_member)))
  end

  test "a minor's contact answer stays out, whoever asks, and an adult's is returned" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red", "own_phone" => "317-555-0100" })
    respond_to_form(@consent_form, :alpha_member, as: :alpha_member, answers: { "choice" => "Red", "own_phone" => "317-555-0100" })

    %i[ admin alpha_manager guardian ward ].each do |viewer|
      result = get_form(viewer, @consent_form, :ward)
      assert_equal "Red", answers(result)["Choice"], "as #{viewer}"
      assert_no_match(/555.?0100/, result.value.to_json, "as #{viewer}")
    end
    assert_match(/555.?0100/, answers(get_form(:alpha_member, @consent_form, :alpha_member))["Own phone"])
  end

  test "if the history can't be read, a minor's answers all stay out" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" })

    without_question_history do
      assert_empty answers(get_form(:admin, @consent_form, :ward))
    end
  end

  test "someone a form leaves every question to others can't update, though they may read it" do
    form = create_world_form("Leaders fill", @alpha)
    form.form_questions.create!(kind: :input, label: "Leader note", data_type: :string, write_permission: "leaders")
    form.form_questions.reset

    assert_equal false, get_form(:alpha_member, form, :alpha_member).value.dig("response", "can_update")
    assert_equal true, get_form(:alpha_manager, form, :alpha_member).value.dig("response", "can_update")
  end

  test "a form with nothing to answer can be updated" do
    form = create_world_form("Read me", @alpha)
    form.form_questions.create!(kind: :statement, body: "Please note.")
    form.form_questions.reset

    assert_equal true, get_form(:alpha_member, form, :alpha_member).value.dig("response", "can_update")
  end

  test "a minor whose only writable question is withheld can still update, as the page counts it" do
    form = create_world_form("Phone only", @alpha)
    form.form_questions.create!(kind: :input, label: "Phone", data_type: :phone)
    form.form_questions.reset

    assert_equal true, get_form(:guardian, form, :ward).value.dig("response", "can_update")
  end

  test "without a person, help text is left out for a question the viewer can't read for anyone" do
    @notes.update!(body: "Anything we should know?")
    @allergy_question.update!(body: "List everything.")
    body = ->(result, label) { result.value["questions"].find { |question| question["label"] == label }["body"] }

    coordinator = get_form(:coordinator, @lunch)
    assert_nil body.call(coordinator, "Allergies")
    assert_equal "Allergies", coordinator.value["questions"].last["label"]
    assert_equal "Anything we should know?", body.call(coordinator, "Notes")
    assert_equal "List everything.", body.call(get_form(:alpha_manager, @lunch), "Allergies")
  end

  test "without a person, what isn't an answer keeps its text for anyone who sees the form" do
    statement = @lunch.form_questions.create!(kind: :statement, body: "Lunch is at noon.")
    @lunch.form_questions.reset

    listed = get_form(:coordinator, @lunch).value["questions"].find { |question| question["id"] == statement.neat_id }
    assert_equal "Lunch is at noon.", listed["body"]
  end

  test "contact questions are left out for a minor, whoever asks, and stay for an adult" do
    %i[ admin alpha_manager guardian ward ].each do |viewer|
      assert_not_includes labels(get_form(viewer, @consent_form, :ward)), "Own phone", "as #{viewer}"
    end
    assert_includes labels(get_form(:alpha_member, @consent_form, :alpha_member)), "Own phone"
  end

  test "someone with no birthday on file counts as a minor" do
    person(:alpha_member).update!(birthday: nil)

    assert_not_includes labels(get_form(:admin, @consent_form, :alpha_member)), "Own phone"
  end

  test "questions linked to a built-in contact field are left out for a minor" do
    PersonField.ensure_system_fields!
    linked = @consent_form.form_questions.create!(kind: :input, label: "Linked phone", person_field: PersonField.system_field("phone_number"), profile_mode: :prefill)
    @consent_form.form_questions.reset

    assert_not_includes labels(get_form(:admin, @consent_form, :ward)), linked.label
    assert_includes labels(get_form(:admin, @consent_form, :alpha_member)), linked.label
  end

  test "a question that used to be a contact question stays out for a minor" do
    @own_phone.update!(data_type: :string)

    assert_not_includes labels(get_form(:admin, @consent_form, :ward)), "Own phone"
    assert_includes labels(get_form(:admin, @consent_form, :alpha_member)), "Own phone"
  end

  test "if the history can't be read, a minor's answerable questions all stay out, and what isn't answered stays" do
    without_question_history do
      assert_equal [ "Parent consent" ], labels(get_form(:admin, @consent_form, :ward))
      assert_includes labels(get_form(:admin, @consent_form, :alpha_member)), "Comment"
    end
  end

  test "the list without a person holds the contact questions: there's no person to judge" do
    assert_includes labels(get_form(:admin)), "Own phone"
  end

  test "waiting_for doesn't name a contact question withheld for a minor" do
    @own_phone.update!(required: true)
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" }, submit: false)
    @own_phone.update!(write_permission: "admin")
    @consent_form.form_questions.reset
    submission = submission_of(@consent_form, :ward)
    assert_empty submission.submit!(person(:guardian), FormAccess.new(person(:guardian), person(:ward), @consent_form))

    waiting_for = get_form(:guardian, @consent_form, :ward).value.dig("response", "waiting_for")

    assert_includes waiting_for, "another required answer"
    assert_empty waiting_for.grep(/Own phone/)
  end

  test "needs the forms feature" do
    with_feature(:forms, false) { assert_equal "Feature off", get_form(:admin).error }
  end
end
