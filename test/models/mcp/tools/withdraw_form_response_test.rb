require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"
require_relative "../../../support/mcp_form_responses_world"

class Mcp::Tools::WithdrawFormResponseTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
    plain_form
    %i[ alpha_member ward ].each do |subject|
      respond_to_form(plain_form, subject, as: subject == :ward ? :guardian : subject, answers: { "pick" => "x" })
    end
  end

  def withdraw(viewer, subject, form: plain_form)
    call_tool("withdraw_form_response", user: user(viewer), form_id: form.neat_id, person_id: person(subject).neat_id)
  end

  test "the person withdraws their own, and gets the response back" do
    result = withdraw(:alpha_member, :alpha_member)

    assert_nil result.error
    assert_equal "withdrawn", result.value.dig("response", "status")
    submission = submission_of(plain_form, :alpha_member)
    assert submission.withdrawn?
    assert_equal submission, result.changed
    assert_nil submission.form_response.active_submission
  end

  test "an admin, a team manager and a guardian withdraw for someone they may" do
    assert_nil withdraw(:guardian, :ward).error
    assert_nil withdraw(:alpha_manager, :alpha_member).error

    respond_to_form(plain_form, :alpha_member, as: :alpha_member, answers: { "pick" => "y" })
    assert_nil withdraw(:admin, :alpha_member).error
  end

  test "a plain member on another team gets Not found and nothing changes" do
    result = assert_nothing_changes { withdraw(:beta_member, :alpha_member) }

    assert_equal "Not found", result.error
    assert submission_of(plain_form, :alpha_member).active?
  end

  test "someone who can read but not respond gets Not allowed" do
    result = assert_nothing_changes do
      call_tool("withdraw_form_response", user: user(:coordinator), form_id: @lunch.neat_id, person_id: person(:alpha_member).neat_id)
    end

    assert_equal "Not allowed", result.error
  end

  test "nothing submitted, or an update in progress, is Not allowed" do
    assert_equal "Not allowed", assert_nothing_changes { withdraw(:alpha_manager, :alpha_manager) }.error

    call_tool("save_form_answers", user: user(:alpha_member), form_id: plain_form.neat_id, person_id: person(:alpha_member).neat_id, answers: { @plain_pick.neat_id => "newer" })
    assert_equal "Not allowed", assert_nothing_changes { withdraw(:alpha_member, :alpha_member) }.error
  end

  test "signatures are revoked by the token's user and the audit trail names them" do
    save_answers(:alpha_member, :alpha_member, { @choice => "Red" }, submit: true)
    call_tool("sign_form_response", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id,
      question_id: @signature.neat_id, typed_name: "AlphaMember World")

    assert_nil withdraw(:alpha_manager, :alpha_member, form: @consent_form).error

    signature = FormSignature.joins(:form_submission).find_by(form_submissions: { id: submission_of(@consent_form, :alpha_member).id })
    assert_not signature.standing?
    assert_equal person(:alpha_manager), signature.revoked_by
    assert_equal user(:alpha_manager).id.to_s, AuditLog.where(item_type: "FormSubmission").order(:created_at).last.whodunnit
  end

  test "the completion badge goes with it, and the incomplete hook runs" do
    Hook.create!(name: "Test", event: "form_responses - incomplete", code: "Thread.current[:mcp_incomplete] = true")
    Thread.current[:mcp_incomplete] = nil

    withdraw(:alpha_member, :alpha_member)

    assert Thread.current[:mcp_incomplete]
  end

  test "a minor's contact questions stay out of the result" do
    assert_not_includes withdraw(:guardian, :ward, form: plain_form).value["questions"].map { |question| question["type"] }, "phone"

    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" })
    sign(@consent_form, :ward, as: :guardian)
    result = withdraw(:guardian, :ward, form: @consent_form)
    assert_nil result.error
    assert_not_includes result.value["questions"].map { |question| question["label"] }, "Own phone"
  end

  test "needs write scope and writes switched on" do
    assert_equal "Not allowed", call_tool("withdraw_form_response", user: user(:alpha_member), scopes: "mcp_read", form_id: plain_form.neat_id, person_id: person(:alpha_member).neat_id).error
    assert_equal "Writes disabled", call_tool("withdraw_form_response", user: user(:alpha_member), writes_enabled: false, form_id: plain_form.neat_id, person_id: person(:alpha_member).neat_id).error
  end

  def sign(form, subject, as:)
    signer = person(as)
    error = submission_of(form, subject).sign!(form.signature_questions.first, signer: signer, typed_name: "#{signer.first_name} #{signer.last_name}", access: FormAccess.new(signer, person(subject), form))
    raise error if error
  end
end
