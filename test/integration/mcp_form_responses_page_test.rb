require "test_helper"
require_relative "../support/mcp_world"
require_relative "../support/mcp_forms_world"
require_relative "../support/mcp_form_responses_world"

# Each write through the real page and through the tool, with the same input, compared
# by what's stored afterwards. Each pair runs in a rolled-back transaction, so both
# sides start from the same data.
class McpFormResponsesPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
  end

  # What a response stores, without IDs or times.
  def stored(form, subject)
    response = form.form_responses.find_by(subject: person(subject))
    return nil unless response

    response.reload
    submissions = response.form_submissions.reset.map do |submission|
      { number: submission.number, status: submission.status, answers: submission.answers, created_by: submission.created_by_id, submitted_by: submission.submitted_by_id,
        profile_skipped: submission.profile_skipped, signatures: submission.form_signatures.reset.map { |signature| [ signature.signer_id, signature.signer_role, signature.typed_name, signature.revoked_at.present? ] } }
    end
    { status: response.status, active: response.active_submission&.number, update_in_progress: response.update_in_progress, submissions: submissions }
  end

  # Runs the page's request and the tool's call from the same start.
  def compare(form, subject, viewer, page:, tool:)
    page_outcome = attempt(form, subject) do
      sign_in user(viewer)
      page.call
      sign_out user(viewer)
    end
    tool_outcome = attempt(form, subject) { tool.call }

    assert_equal [ page_outcome ], [ tool_outcome ]
    page_outcome
  end

  def attempt(form, subject)
    outcome = nil
    # Not joinable, or a rollback inside the request or the tool wouldn't undo anything.
    FormResponse.transaction(requires_new: true, joinable: false) do
      yield
      outcome = stored(form, subject)
      raise ActiveRecord::Rollback
    end
    outcome
  end

  def page_answers(question_answers)
    { form_response: { answers: question_answers.transform_keys(&:key) } }
  end

  test "saving a draft: the page and the tool store the same" do
    outcome = compare(@consent_form, :alpha_member, :alpha_member,
      page: -> { patch form_response_path(@consent_form, person(:alpha_member)), params: page_answers({ @comment => "hi", @choice => "Red" }).merge(save: "1") },
      tool: -> { save_answers(:alpha_member, :alpha_member, { @comment => "hi", @choice => "Red" }) })

    assert_equal "draft", outcome[:status]
    assert_equal({ "comment" => "hi", "choice" => "Red" }, outcome[:submissions].first[:answers])
  end

  test "submitting: the page and the tool store the same" do
    outcome = compare(@consent_form, :ward, :guardian,
      page: -> { patch form_response_path(@consent_form, person(:ward)), params: page_answers({ @choice => "Red", @agree => "1" }).merge(submit: "1") },
      tool: -> { save_answers(:guardian, :ward, { @choice => "Red", @agree => true }, submit: true) })

    assert_equal "waiting", outcome[:status]
    assert_equal person(:guardian).id, outcome[:submissions].first[:submitted_by]
  end

  test "submitting with what's required missing leaves the same draft on both" do
    outcome = compare(@consent_form, :alpha_member, :alpha_member,
      page: -> { patch form_response_path(@consent_form, person(:alpha_member)), params: page_answers({ @comment => "kept" }).merge(submit: "1") },
      tool: -> { save_answers(:alpha_member, :alpha_member, { @comment => "kept" }, submit: true) })

    assert_equal "draft", outcome[:status]
    assert_equal({ "comment" => "kept" }, outcome[:submissions].first[:answers])
  end

  test "a value the form refuses saves nothing on both" do
    outcome = compare(@consent_form, :alpha_member, :alpha_member,
      page: -> { patch form_response_path(@consent_form, person(:alpha_member)), params: page_answers({ @comment => "x", @choice => "Green" }) },
      tool: -> { save_answers(:alpha_member, :alpha_member, { @comment => "x", @choice => "Green" }) })

    assert_nil outcome
  end

  test "someone refused by the policy saves nothing on both" do
    outcome = compare(@consent_form, :alpha_member, :beta_member,
      page: -> { patch form_response_path(@consent_form, person(:alpha_member)), params: page_answers({ @comment => "x" }) },
      tool: -> { save_answers(:beta_member, :alpha_member, { @comment => "x" }) })

    assert_nil outcome
  end

  test "a closed form refuses a member and takes a leader's late entry, on both" do
    @consent_form.update!(status: :closed, late_entry: :leaders)

    refused = compare(@consent_form, :alpha_member, :alpha_member,
      page: -> { patch form_response_path(@consent_form, person(:alpha_member)), params: page_answers({ @comment => "x" }) },
      tool: -> { save_answers(:alpha_member, :alpha_member, { @comment => "x" }) })
    assert_nil refused

    allowed = compare(@consent_form, :alpha_member, :alpha_manager,
      page: -> { patch form_response_path(@consent_form, person(:alpha_member)), params: page_answers({ @comment => "late" }) },
      tool: -> { save_answers(:alpha_manager, :alpha_member, { @comment => "late" }) })
    assert_equal({ "comment" => "late" }, allowed[:submissions].first[:answers])
  end

  test "a mapped answer reaches the profile the same on both, and an unwritable one doesn't" do
    form = create_world_form("Sizes", @alpha)
    size = form.form_questions.create!(kind: :input, label: "Size", person_field: @size_field, profile_mode: :update_profile)
    form.form_questions.create!(kind: :input, label: "Note", data_type: :string)
    form.form_questions.reset

    values = []
    [ -> { sign_in user(:alpha_manager); patch form_response_path(form, person(:alpha_member)), params: page_answers({ size => "XL" }).merge(submit: "1"); sign_out user(:alpha_manager) },
      -> { save_answers(:alpha_manager, :alpha_member, { size => "XL" }, form: form, submit: true) } ].each do |write|
      FormResponse.transaction(requires_new: true, joinable: false) do
        write.call
        values << [ person(:alpha_member).reload.field_value(@size_field), stored(form, :alpha_member) ]
        raise ActiveRecord::Rollback
      end
    end
    person(:alpha_member).reload

    assert_equal "XL", values.first.first
    assert_equal values.first, values.last

    # The page drops the answer without a word, and the tool refuses it. Neither writes.
    @size_field.update!(write_permission: "self")
    FormResponse.transaction(requires_new: true, joinable: false) do
      sign_in user(:alpha_manager)
      patch form_response_path(form, person(:alpha_member)), params: page_answers({ size => "XXL" }).merge(submit: "1")
      sign_out user(:alpha_manager)
      assert_not_equal "XXL", person(:alpha_member).reload.field_value(@size_field)
      raise ActiveRecord::Rollback
    end
    assert_match(/\ANot allowed: Size\./, save_answers(:alpha_manager, :alpha_member, { size => "XXL" }, form: form, submit: true).error)
    assert_not_equal "XXL", person(:alpha_member).reload.field_value(@size_field)
  end

  test "withdrawing: allowed and refused, the same on both" do
    plain_form
    respond_to_form(plain_form, :alpha_member, as: :alpha_member, answers: { "pick" => "x" })

    allowed = compare(plain_form, :alpha_member, :alpha_member,
      page: -> { post withdraw_form_response_path(plain_form, person(:alpha_member)) },
      tool: -> { call_tool("withdraw_form_response", user: user(:alpha_member), form_id: plain_form.neat_id, person_id: person(:alpha_member).neat_id) })
    assert_equal "withdrawn", allowed[:status]

    refused = compare(plain_form, :alpha_member, :beta_member,
      page: -> { post withdraw_form_response_path(plain_form, person(:alpha_member)) },
      tool: -> { call_tool("withdraw_form_response", user: user(:beta_member), form_id: plain_form.neat_id, person_id: person(:alpha_member).neat_id) })
    assert_equal "complete", refused[:status]
  end

  test "signing: allowed, refused by role and refused by name, the same on both" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" })
    call = ->(viewer, name) {
      call_tool("sign_form_response", user: user(viewer), form_id: @consent_form.neat_id, person_id: person(:ward).neat_id, question_id: @signature.neat_id, typed_name: name)
    }

    allowed = compare(@consent_form, :ward, :guardian,
      page: -> { post sign_form_response_path(@consent_form, person(:ward)), params: { question_id: @signature.id, typed_name: "Guardian World" } },
      tool: -> { call.call(:guardian, "Guardian World") })
    assert_equal "complete", allowed[:status]
    assert_equal [ [ person(:guardian).id, "guardian", "Guardian World", false ] ], allowed[:submissions].first[:signatures]

    by_role = compare(@consent_form, :ward, :ward,
      page: -> { post sign_form_response_path(@consent_form, person(:ward)), params: { question_id: @signature.id, typed_name: "Ward World" } },
      tool: -> { call.call(:ward, "Ward World") })
    assert_equal "waiting", by_role[:status]

    by_name = compare(@consent_form, :ward, :guardian,
      page: -> { post sign_form_response_path(@consent_form, person(:ward)), params: { question_id: @signature.id, typed_name: "Someone Else" } },
      tool: -> { call.call(:guardian, "Someone Else") })
    assert_empty by_name[:submissions].first[:signatures]
  end

  # Whether the edit page loads and offers its Submit button.
  def page_offers_submit?(form, viewer, subject)
    sign_in user(viewer)
    get edit_form_response_path(form, person(subject))
    response.successful? && css_select("[name=submit]").any?
  ensure
    sign_out user(viewer)
  end

  test "who may fill in matches the page's Submit button for each kind of viewer" do
    { alpha_member: :alpha_member, alpha_manager: :alpha_member, admin: :alpha_member, guardian: :ward, beta_member: :alpha_member, coordinator: :alpha_member }.each do |viewer, subject|
      tool = call_tool("get_form", user: user(viewer), form_id: @lunch.neat_id, person_id: person(subject).neat_id)
      assert_equal page_offers_submit?(@lunch, viewer, subject), tool.value&.dig("response", "can_update") == true, "#{viewer} for #{subject}"
    end
  end

  test "the tool takes a submit exactly when the page offers the button" do
    leaders = create_world_form("Leaders fill", @alpha)
    leaders.form_questions.create!(kind: :input, label: "Leader note", data_type: :string, write_permission: "leaders")
    nothing = create_world_form("Read me", @alpha)
    nothing.form_questions.create!(kind: :statement, body: "Please note.")
    phone = create_world_form("Phone only", @alpha)
    phone.form_questions.create!(kind: :input, label: "Phone", data_type: :phone)
    [ leaders, nothing, phone ].each { |form| form.form_questions.reset }

    { [ leaders, :alpha_member, :alpha_member ] => false, [ leaders, :alpha_manager, :alpha_member ] => true,
      [ nothing, :alpha_member, :alpha_member ] => true, [ phone, :guardian, :ward ] => true }.each do |(form, viewer, subject), expected|
      assert_equal expected, page_offers_submit?(form, viewer, subject), "page: #{form.title} as #{viewer}"
      assert_equal expected, call_tool("get_form", user: user(viewer), form_id: form.neat_id, person_id: person(subject).neat_id).value.dig("response", "can_update"), "get_form: #{form.title} as #{viewer}"

      result = call_tool("save_form_answers", user: user(viewer), form_id: form.neat_id, person_id: person(subject).neat_id, answers: {}, submit: true)
      assert_equal expected, result.error.nil?, "save: #{form.title} as #{viewer}: #{result.error}"
    end
  end

  test "a signer reads the same pending answers on the page and through the tool" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red", "comment" => "for the trip" })

    sign_in user(:guardian)
    get form_response_path(@consent_form, person(:ward))
    assert_response :success
    assert_includes response.body, "signing these answers"
    assert_includes response.body, "for the trip"
    sign_out user(:guardian)

    questions = call_tool("get_form", user: user(:guardian), form_id: @consent_form.neat_id, person_id: person(:ward).neat_id).value["questions"]
    assert_equal "for the trip", questions.find { |question| question["label"] == "Comment" }["answer"]
  end

  test "someone who can only read sees a draft's readable answers on the page, and the same through the tool" do
    @lunch.form_responses.find_by(subject: person(:alpha_member)).active_submission.withdraw!(by: person(:alpha_member))
    respond_to_form(@lunch, :alpha_member, as: :alpha_member, answers: { "sandwich" => "Big John", "allergies" => "peanut" }, submit: false)

    sign_in user(:coordinator)
    get form_response_path(@lunch, person(:alpha_member))
    assert_response :success
    assert_includes response.body, "Big John"
    assert_not_includes response.body, "peanut"
    sign_out user(:coordinator)

    json = call_tool("get_form", user: user(:coordinator), form_id: @lunch.neat_id, person_id: person(:alpha_member).neat_id).value
    assert_equal "Big John", json["questions"].find { |question| question["label"] == "Sandwich" }["answer"]
    assert_not_includes json.to_json, "peanut"
  end

  test "the page and get_form show the same answerable questions for a viewer" do
    @comment.update!(read_permission: "self_and_leaders")

    sign_in user(:guardian)
    get edit_form_response_path(@consent_form, person(:ward))
    assert_response :success
    assert_includes response.body, "Choice"
    assert_not_includes response.body, "form_question_comment"

    labels = call_tool("get_form", user: user(:guardian), form_id: @consent_form.neat_id, person_id: person(:ward).neat_id).value["questions"].map { |question| question["label"] }
    assert_includes labels, "Choice"
    assert_not_includes labels, "Comment"
  end
end

# Over the real /mcp endpoint: what the form tools' arguments leave in the Rails log,
# at the production level.
class McpFormResponsesLogTest < ActionDispatch::IntegrationTest
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
  end

  def logged_line_for(tool, arguments, viewer:)
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    with_settings(mcp_write_enabled: "true") do
      mcp_post(mcp_token(user(viewer), scopes: "mcp_read mcp_write"), "tools/call", { name: tool, arguments: arguments })
    end
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "answers aren't in the log, stored or refused, and the IDs still are" do
    log = logged_line_for("save_form_answers", { form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: { @comment.neat_id => "Answersecret" } }, viewer: :alpha_member)
    assert_includes log, "Parameters"
    assert_includes log, "[FILTERED]"
    assert_not_includes log, "Answersecret"
    assert_includes log, person(:alpha_member).neat_id
    assert_equal "Answersecret", submission_of(@consent_form, :alpha_member).answers["comment"]

    log = logged_line_for("save_form_answers", { form_id: @consent_form.neat_id, person_id: person(:ward).neat_id, answers: { @own_phone.neat_id => "555-0177" } }, viewer: :admin)
    assert_not_includes log, "555-0177"

    log = logged_line_for("save_form_answers", { form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: {}, answer: "Answersecret" }, viewer: :alpha_member)
    assert_not_includes log, "Answersecret"
  end

  test "the typed name isn't in the log, stored or refused, and neither is a signature the tool doesn't take" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" })

    base = { form_id: @consent_form.neat_id, person_id: person(:ward).neat_id, question_id: @signature.neat_id }
    log = logged_line_for("sign_form_response", base.merge(typed_name: "Wrongname World"), viewer: :guardian)
    assert_includes log, "[FILTERED]"
    assert_not_includes log, "Wrongname"

    log = logged_line_for("sign_form_response", base.merge(typed_name: "Guardian World"), viewer: :guardian)
    assert_not_includes log, "Guardian World"

    log = logged_line_for("sign_form_response", base.merge(typed_name: "x", signature: "Signaturesecret"), viewer: :guardian)
    assert_not_includes log, "Signaturesecret"
  end
end
