require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"
require_relative "../../../support/mcp_form_responses_world"

class Mcp::Tools::SignFormResponseTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" })
    respond_to_form(@consent_form, :alpha_member, as: :alpha_member, answers: { "choice" => "Blue" })
  end

  def sign_form(viewer, subject, typed_name, question: @signature, form: @consent_form)
    call_tool("sign_form_response", user: user(viewer), form_id: form.neat_id, person_id: person(subject).neat_id,
      question_id: question.neat_id, typed_name: typed_name)
  end

  test "an adult signs for themselves: recorded as the token's user, and the response completes" do
    result = sign_form(:alpha_member, :alpha_member, "alphamember  world")

    assert_nil result.error
    assert_equal "complete", result.value.dig("response", "status")
    signature = submission_of(@consent_form, :alpha_member).form_signatures.first
    assert_equal person(:alpha_member), signature.signer
    assert signature.signed_as_subject?
    assert_equal "alphamember world", signature.typed_name
    assert_equal signature, result.changed
    assert_includes result.changed_records, submission_of(@consent_form, :alpha_member)
  end

  test "a guardian signs for a minor, in the guardian's own name and role" do
    result = sign_form(:guardian, :ward, "Guardian World")

    assert_nil result.error
    signature = submission_of(@consent_form, :ward).form_signatures.first
    assert_equal person(:guardian), signature.signer
    assert signature.signed_as_guardian?
  end

  test "the record says it came through a client: no IP, and the client's name when known" do
    sign_form(:guardian, :ward, "Guardian World")

    signature = submission_of(@consent_form, :ward).form_signatures.first
    assert_nil signature.ip_address
    assert_equal "MCP client", signature.user_agent

    respond_to_form(plain_consent = create_consent(:guardian), :ward, as: :guardian, answers: {})
    context = Mcp::Context.new(user: user(:guardian), scopes: [ "mcp_write" ], application: mcp_application, request_id: "test")
    with_settings(mcp_write_enabled: "true") do
      Mcp::Tools::SignFormResponse.run(context, { form_id: plain_consent.neat_id, person_id: person(:ward).neat_id,
        question_id: plain_consent.signature_questions.first.neat_id, typed_name: "Guardian World" })
    end
    assert_equal "MCP client: MCP Client", submission_of(plain_consent, :ward).form_signatures.first.user_agent
  end

  test "the audit trail names the token's user" do
    sign_form(:guardian, :ward, "Guardian World")

    assert_equal user(:guardian).id.to_s, AuditLog.where(item_type: "FormSignature").order(:created_at).last.whodunnit
  end

  test "someone else's name is refused, naming only the signer's own" do
    result = assert_nothing_changes { sign_form(:guardian, :ward, "Ward World") }

    assert_match(/Type your full name exactly as it appears on your account: Guardian World/, result.error)
    assert_nil result.changed
  end

  test "a blank name is refused" do
    assert_match(/Type your full name/, assert_nothing_changes { sign_form(:guardian, :ward, "  ") }.error)
  end

  test "a minor can't sign for themselves" do
    assert_equal "Not allowed", assert_nothing_changes { sign_form(:ward, :ward, "Ward World") }.error
  end

  test "someone with no birthday on file waits for a guardian" do
    person(:alpha_member).update!(birthday: nil)

    assert_equal "Not allowed", assert_nothing_changes { sign_form(:alpha_member, :alpha_member, "AlphaMember World") }.error
  end

  test "a plain member on another team gets Not found" do
    assert_equal "Not found", assert_nothing_changes { sign_form(:beta_member, :alpha_member, "BetaMember World") }.error
  end

  test "a team manager and an admin can't sign a question that isn't a leader's" do
    assert_equal "Not allowed", assert_nothing_changes { sign_form(:alpha_manager, :ward, "AlphaManager World") }.error
    assert_equal "Not allowed", assert_nothing_changes { sign_form(:admin, :ward, "Admin World") }.error
  end

  test "a leader records a paper signature on a question that asks for one, in their own name" do
    form = create_consent(:leader)
    respond_to_form(form, :alpha_member, as: :alpha_member, answers: {})
    question = form.signature_questions.first

    result = sign_form(:alpha_manager, :alpha_member, "AlphaManager World", question: question, form: form)

    assert_nil result.error
    signature = submission_of(form, :alpha_member).form_signatures.first
    assert_equal person(:alpha_manager), signature.signer
    assert signature.signed_as_leader?
    assert_equal "Not allowed", assert_nothing_changes { sign_form(:alpha_member, :alpha_member, "AlphaMember World", question: question, form: form) }.error
  end

  test "nothing waiting to be signed is Not allowed" do
    save_answers(:alpha_manager, :alpha_manager, { @comment => "draft" })

    assert_equal "Not allowed", assert_nothing_changes { sign_form(:alpha_manager, :alpha_manager, "AlphaManager World") }.error

    sign_form(:guardian, :ward, "Guardian World")
    assert_equal "Not allowed", assert_nothing_changes { sign_form(:guardian, :ward, "Guardian World") }.error
  end

  test "a signature already given, with another still open, is a refusal that changes nothing" do
    form = create_consent(:subject)
    second = form.form_questions.create!(kind: :signature, label: "Second", signer: :subject)
    form.form_questions.reset
    respond_to_form(form, :alpha_member, as: :alpha_member, answers: {})
    assert_nil sign_form(:alpha_member, :alpha_member, "AlphaMember World", question: form.signature_questions.first, form: form).error

    result = assert_nothing_changes { sign_form(:alpha_member, :alpha_member, "AlphaMember World", question: form.signature_questions.first, form: form) }

    assert_equal "This has already been signed.", result.error
    assert second
  end

  test "a question that isn't a signature on this form is Not found" do
    assert_equal "Not found", assert_nothing_changes { sign_form(:guardian, :ward, "Guardian World", question: @choice) }.error
    elsewhere = create_consent(:guardian).signature_questions.first
    assert_equal "Not found", assert_nothing_changes { sign_form(:guardian, :ward, "Guardian World", question: elsewhere) }.error
  end

  test "signing after the form closes still works, as on the page" do
    @consent_form.update!(status: :closed)

    assert_nil sign_form(:guardian, :ward, "Guardian World").error
  end

  test "the last signature writes mapped answers to the profile, as who submitted" do
    respond_to_form(@consent_form, :alpha_manager, as: :alpha_manager, answers: { "choice" => "Red", "size" => "M" })

    result = sign_form(:alpha_manager, :alpha_manager, "AlphaManager World")

    assert_nil result.error
    assert_equal "M", person(:alpha_manager).reload.field_value(@size_field)
    assert_includes result.changed_records, person(:alpha_manager)
  end

  test "the call log masks the typed name" do
    sign_form(:guardian, :ward, "Guardian World")

    row = McpToolCall.where(tool: "sign_form_response").order(:created_at).last
    assert_equal Mcp::Tool::MASKED, row.arguments["typed_name"]
    assert_not_includes row.arguments.to_json, "Guardian World"
  end

  test "its description warns that it records a signature in the member's name" do
    assert_match(/records a signature in the member's name/i, Mcp::Tools::SignFormResponse.description)
  end

  test "an argument the page doesn't ask for is refused by name" do
    result = assert_nothing_changes do
      call_tool("sign_form_response", user: user(:guardian), form_id: @consent_form.neat_id, person_id: person(:ward).neat_id,
        question_id: @signature.neat_id, typed_name: "Guardian World", signer_id: person(:admin).neat_id)
    end

    assert_match(/signer_id/, result.error)
  end

  test "needs write scope and writes switched on" do
    assert_equal "Not allowed", call_tool("sign_form_response", user: user(:guardian), scopes: "mcp_read", form_id: @consent_form.neat_id, person_id: person(:ward).neat_id, question_id: @signature.neat_id, typed_name: "Guardian World").error
    assert_equal "Writes disabled", call_tool("sign_form_response", user: user(:guardian), writes_enabled: false, form_id: @consent_form.neat_id, person_id: person(:ward).neat_id, question_id: @signature.neat_id, typed_name: "Guardian World").error
  end

  private

  def create_consent(signer)
    form = create_world_form("Consent #{signer}", @alpha)
    form.form_questions.create!(kind: :signature, label: "Sign #{signer}", signer: signer)
    form.form_questions.reset
    form
  end
end
