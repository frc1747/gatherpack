require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_forms_world"
require_relative "../../../support/mcp_form_responses_world"

class Mcp::Tools::SaveFormAnswersTest < ActiveSupport::TestCase
  include McpWorld
  include McpFormsWorld
  include McpFormResponsesWorld

  setup do
    build_mcp_world
    build_mcp_forms_world
    build_mcp_form_responses_world
  end

  test "a member saves a draft of their own answers, and only the given ones" do
    result = save_answers(:alpha_member, :alpha_member, { @comment => "first" })
    assert_nil result.error
    assert_equal "draft", result.value.dig("response", "status")

    save_answers(:alpha_member, :alpha_member, { @choice => "Red" })

    submission = submission_of(@consent_form, :alpha_member)
    assert_equal "first", submission.answers["comment"]
    assert_equal "Red", submission.answers["choice"]
    assert_equal person(:alpha_member), submission.created_by
    assert_equal submission, result.changed
  end

  test "an admin, a team manager and a guardian answer for someone they may" do
    assert_nil save_answers(:admin, :alpha_member, { @comment => "a" }).error
    assert_nil save_answers(:alpha_manager, :alpha_member, { @comment => "b" }).error
    assert_nil save_answers(:guardian, :ward, { @comment => "c" }).error
    assert_equal "c", submission_of(@consent_form, :ward).answers["comment"]
    assert_equal "b", submission_of(@consent_form, :alpha_member).answers["comment"]
  end

  test "a plain member on another team gets Not found and nothing changes" do
    result = assert_nothing_changes { save_answers(:beta_member, :alpha_member, { @comment => "x" }) }

    assert_equal "Not found", result.error
  end

  test "someone who can read but not answer gets Not allowed and nothing changes" do
    result = assert_nothing_changes { call_tool("save_form_answers", user: user(:coordinator), form_id: @lunch.neat_id, person_id: person(:alpha_manager).neat_id, answers: { @sandwich.neat_id => "Slim 4" }) }

    assert_equal "Not allowed", result.error
  end

  test "a closed form takes no answers from a member, and takes a late one from a leader when it allows them" do
    @consent_form.update!(status: :closed, late_entry: :leaders)

    assert_equal "Not allowed", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @comment => "x" }) }.error
    assert_nil save_answers(:alpha_manager, :alpha_member, { @comment => "late" }).error
  end

  test "an answer to a question the viewer can't write is refused by name, and nothing is saved" do
    @comment.update!(write_permission: "self_and_leaders")

    result = assert_nothing_changes { save_answers(:guardian, :ward, { @comment => "x", @choice => "Red" }) }

    assert_match(/\ANot allowed: Comment\./, result.error)
    assert_equal :denied, result.outcome
  end

  test "an unreadable question and an unknown ID get the same words, and the ID isn't repeated" do
    @comment.update!(read_permission: "admin")

    unreadable = assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @comment => "x" }) }
    unknown = assert_nothing_changes do
      call_tool("save_form_answers", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: { "555-0100" => "x" })
    end

    assert_equal unreadable.error, unknown.error
    assert_not_includes unknown.error, "555-0100"
  end

  test "a question from another form is refused" do
    result = assert_nothing_changes do
      call_tool("save_form_answers", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: { @sandwich.neat_id => "Slim 4" })
    end

    assert_match(/\ANot allowed/, result.error)
  end

  test "a value the form would refuse is refused by question, without quoting it, and nothing is saved" do
    result = assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @comment => "kept out", @choice => "Green" }) }

    assert_match(/Choice \(#{@choice.neat_id}\) isn't one of the choices/, result.error)
    assert_not_includes result.error, "Green"
    assert_nil result.changed
  end

  test "yes/no takes only true, false or null: no isn't ticked" do
    [ "no", "No", 0, 0.0, 2 ].each do |value|
      result = assert_nothing_changes do
        call_tool("save_form_answers", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: { @agree.neat_id => value })
      end
      assert_equal "Agree takes true or false", result.error
    end

    save_answers(:alpha_member, :alpha_member, { @agree => true })
    assert_equal true, submission_of(@consent_form, :alpha_member).answers["agree"]
    save_answers(:alpha_member, :alpha_member, { @agree => false })
    assert_not submission_of(@consent_form, :alpha_member).answers.key?("agree")
  end

  test "null and blank clear an answer" do
    save_answers(:alpha_member, :alpha_member, { @comment => "x" })
    save_answers(:alpha_member, :alpha_member, { @comment => nil })
    assert_not submission_of(@consent_form, :alpha_member).answers.key?("comment")

    save_answers(:alpha_member, :alpha_member, { @comment => "y" })
    save_answers(:alpha_member, :alpha_member, { @comment => "  " })
    assert_not submission_of(@consent_form, :alpha_member).answers.key?("comment")
  end

  test "text types take strings only, and single-line types one line" do
    assert_equal "Choice takes text", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @choice => 5 }) }.error
    assert_equal "Choice takes text", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @choice => [ "Red" ] }) }.error
    assert_equal "Size takes one line", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @size => "a\nb" }) }.error

    assert_nil save_answers(:alpha_member, :alpha_member, { @comment => "two\nlines" }).error
  end

  test "typed questions check their values" do
    number = @consent_form.form_questions.create!(kind: :input, label: "Count", data_type: :integer)
    date = @consent_form.form_questions.create!(kind: :input, label: "When", data_type: :date)
    many = @consent_form.form_questions.create!(kind: :input, label: "Many", data_type: :multi_select, choices: %w[ A B ])
    @consent_form.form_questions.reset

    assert_match(/must be a whole number/, assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { number => "soon" }) }.error)
    assert_equal "Count takes a whole number", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { number => 1.5 }) }.error
    assert_match(/isn't a valid date/, assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { date => "someday" }) }.error)
    assert_equal "When isn't a valid date", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { date => "2" * 200 }) }.error
    assert_equal "Many takes a list of choices", assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { many => [ nil ] }) }.error
    assert_match(/includes a choice/, assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { many => [ "C" ] }) }.error)

    assert_nil save_answers(:alpha_member, :alpha_member, { number => 7, date => "2026-12-01", many => [ "A", "B" ] }).error
    answers = submission_of(@consent_form, :alpha_member).answers
    assert_equal [ 7, "2026-12-01", %w[ A B ] ], answers.values_at("count", "when", "many")
  end

  test "an infinite number and a NUL are refusals, not internal errors" do
    result = assert_nothing_changes do
      call_tool("save_form_answers", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: { @comment.neat_id => Float::INFINITY })
    end
    assert_equal "Comment takes text", result.error

    assert_match(/NUL/, assert_nothing_changes { save_answers(:alpha_member, :alpha_member, { @comment => "a\0b" }) }.error)
  end

  test "an argument the tool doesn't take is refused by name" do
    result = assert_nothing_changes do
      call_tool("save_form_answers", user: user(:alpha_member), form_id: @consent_form.neat_id, person_id: person(:alpha_member).neat_id, answers: {}, notes: "x")
    end

    assert_match(/notes/, result.error)
  end

  def leaders_only_form(required:)
    form = create_world_form("Leaders fill", @alpha)
    @leader_note = form.form_questions.create!(kind: :input, label: "Leader note", data_type: :string, write_permission: "leaders", required: required)
    form.form_questions.reset
    form
  end

  test "someone the page offers no Submit can't complete an empty response" do
    [ false, true ].each do |required|
      form = leaders_only_form(required: required)

      [ { submit: true }, { submit: false } ].each do |options|
        result = assert_nothing_changes { save_answers(:alpha_member, :alpha_member, {}, form: form, **options) }
        assert_equal "Not allowed", result.error
      end
      assert_nil form.form_responses.find_by(subject: person(:alpha_member))
      form.destroy!
    end
  end

  test "whoever the form leaves its questions to answers and submits them" do
    form = leaders_only_form(required: true)

    result = save_answers(:alpha_manager, :alpha_member, { @leader_note => "seen" }, form: form, submit: true)

    assert_nil result.error
    assert_equal "complete", result.value.dig("response", "status")
  end

  test "a form with nothing to answer can be submitted, as on the page" do
    form = create_world_form("Read me", @alpha)
    form.form_questions.create!(kind: :statement, body: "Please note.")
    form.form_questions.reset

    result = save_answers(:alpha_member, :alpha_member, {}, form: form, submit: true)

    assert_nil result.error
    assert_equal "complete", result.value.dig("response", "status")
  end

  test "the result has the saved answers" do
    result = save_answers(:alpha_member, :alpha_member, { @comment => "first" })

    assert_equal "first", result.value["questions"].find { |question| question["label"] == "Comment" }["answer"]
  end

  # A pending response for ward with one of its two signatures given.
  def partly_signed_response
    second = @consent_form.form_questions.create!(kind: :signature, label: "Second", signer: :guardian)
    @consent_form.form_questions.reset
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "choice" => "Red" })
    call_tool("sign_form_response", user: user(:guardian), form_id: @consent_form.neat_id, person_id: person(:ward).neat_id, question_id: second.neat_id, typed_name: "Guardian World")
    submission_of(@consent_form, :ward).form_signatures.first
  end

  test "a signature revoked by changing an answer is logged as changed" do
    signature = partly_signed_response

    result = save_answers(:guardian, :ward, { @comment => "changed" })

    assert_nil result.error
    assert_equal [ submission_of(@consent_form, :ward), signature ], result.changed_records
    assert_not signature.reload.standing?
  end

  test "a signature revoked before a refused submit is logged as changed too" do
    signature = partly_signed_response

    result = save_answers(:guardian, :ward, { @choice => nil }, submit: true)

    assert_match(/Still needed/, result.error)
    assert_includes result.changed_records, signature
    assert_not signature.reload.standing?
  end

  test "a save that revokes nothing logs only the submission" do
    result = save_answers(:alpha_member, :alpha_member, { @comment => "first" })

    assert_equal [ submission_of(@consent_form, :alpha_member) ], result.changed_records
  end

  test "submit logs the completion badge it grants" do
    badge = create_world_badge("Done", team: @alpha)
    plain_form.update!(completion_badge: badge)

    result = save_answers(:alpha_member, :alpha_member, { @plain_pick => "x" }, form: plain_form, submit: true)

    assert_nil result.error
    assert_includes result.changed_records, BadgeAssignment.find_by!(badge: badge, person: person(:alpha_member))
  end

  test "submit activates a form with nothing left to sign, for the page's status and who submitted" do
    plain_form
    result = save_answers(:alpha_member, :alpha_member, { @plain_pick => "x" }, form: plain_form, submit: true)

    assert_nil result.error
    assert_equal "complete", result.value.dig("response", "status")
    submission = submission_of(plain_form, :alpha_member)
    assert submission.active?
    assert_equal person(:alpha_member), submission.submitted_by
    assert_not_nil result.value.dig("response", "submitted_at")
  end

  test "submit with a signature left waits for it" do
    result = save_answers(:alpha_member, :alpha_member, { @choice => "Red" }, submit: true)

    assert_equal "waiting", result.value.dig("response", "status")
    assert submission_of(@consent_form, :alpha_member).pending?
  end

  test "submit with what's missing reports it by question, and the draft stays, as on the page" do
    @agree.update!(required: true)

    result = save_answers(:alpha_member, :alpha_member, { @comment => "kept" }, submit: true)

    assert_match(/saved as a draft, but not submitted/, result.error)
    assert_match(/Choice \(#{@choice.neat_id}\) can't be blank/, result.error)
    assert_match(/Agree \(#{@agree.neat_id}\) must be ticked/, result.error)
    submission = submission_of(@consent_form, :alpha_member)
    assert submission.draft?
    assert_equal "kept", submission.answers["comment"]
    assert_equal submission, result.changed
    assert_equal "draft", submission.form_response.status
  end

  test "submit with no new answers submits the draft" do
    save_answers(:alpha_member, :alpha_member, { @choice => "Red" })

    result = save_answers(:alpha_member, :alpha_member, {}, submit: true)

    assert_equal "waiting", result.value.dig("response", "status")
  end

  test "changing a signed version's answers returns it to a draft and revokes the signature" do
    @consent_form.form_questions.create!(kind: :signature, label: "Second", signer: :subject)
    @consent_form.form_questions.reset
    save_answers(:alpha_member, :alpha_member, { @choice => "Red" }, submit: true)
    submission = submission_of(@consent_form, :alpha_member)
    assert_nil submission.sign!(@signature, signer: person(:alpha_member), typed_name: "AlphaMember World", access: FormAccess.new(person(:alpha_member), person(:alpha_member), @consent_form))

    save_answers(:alpha_member, :alpha_member, { @choice => "Blue" })

    submission.reload
    assert submission.draft?
    assert_empty submission.standing_signatures
    assert_equal person(:alpha_member), submission.form_signatures.first.revoked_by
  end

  test "a mapped question writes the person field on activation, with the token's user acting, and logs the person as changed" do
    form = create_world_form("Sizes", @alpha)
    size = form.form_questions.create!(kind: :input, label: "Size", person_field: @size_field, profile_mode: :update_profile)
    form.form_questions.reset

    result = save_answers(:alpha_manager, :alpha_member, { size => "XL" }, form: form, submit: true)

    assert_nil result.error
    assert_equal "XL", person(:alpha_member).reload.field_value(@size_field)
    assert_includes result.changed_records, person(:alpha_member)
    assert_equal person(:alpha_manager).id, person(:alpha_member).person_field_values.find_by(person_field: @size_field).updated_by_id
    assert_empty result.value.dig("response", "not_copied_to_profile")
  end

  test "a mapped question isn't written until activation" do
    form = create_world_form("Sizes", @alpha)
    size = form.form_questions.create!(kind: :input, label: "Size", person_field: @size_field, profile_mode: :update_profile)
    form.form_questions.reset

    save_answers(:alpha_manager, :alpha_member, { size => "XL" }, form: form)

    assert_nil person(:alpha_member).reload.field_value(@size_field)
  end

  test "a mapped question the viewer can't write is refused by name, and the field stays" do
    @size_field.update!(write_permission: "self")
    person(:alpha_member).set_field_value(@size_field, "S")

    result = assert_nothing_changes { save_answers(:alpha_manager, :alpha_member, { @size => "XL" }) }

    assert_match(/\ANot allowed: Size\./, result.error)
    assert_equal "S", person(:alpha_member).reload.field_value(@size_field)
  end

  test "an answer that couldn't reach the profile is reported, not claimed" do
    form = create_world_form("Sizes", @alpha)
    size = form.form_questions.create!(kind: :input, label: "Size", person_field: @size_field, profile_mode: :update_profile)
    form.form_questions.create!(kind: :input, label: "Note", data_type: :string)
    form.form_questions.reset
    @size_field.update!(write_permission: "self")
    save_answers(:alpha_member, :alpha_member, { size => "XL" }, form: form)

    result = save_answers(:alpha_manager, :alpha_member, {}, form: form, submit: true)

    assert_nil result.error
    assert_equal [ "Size" ], result.value.dig("response", "not_copied_to_profile")
    assert_not_includes result.changed_records, person(:alpha_member)
    assert_nil person(:alpha_member).reload.field_value(@size_field)
  end

  test "a contact question for a minor is refused, whoever asks, in the words of an unknown question" do
    %i[ admin alpha_manager guardian ].each do |viewer|
      result = assert_nothing_changes { save_answers(viewer, :ward, { @own_phone => "555-0100", @comment => "x" }) }

      assert_equal "Not allowed: 1 question that can't be answered here. Nothing was saved.", result.error
      assert_not_includes result.error, "Own phone"
    end
  end

  test "a contact question for an adult is answered" do
    assert_nil save_answers(:alpha_manager, :alpha_member, { @own_phone => "555-0100" }).error
    assert_equal "555-0100", submission_of(@consent_form, :alpha_member).answers["own_phone"]
  end

  test "a built-in contact field can't be set through a minor's form, so a birthday can't lift the rule" do
    PersonField.ensure_system_fields!
    birthday = @consent_form.form_questions.create!(kind: :input, label: "Birthday", person_field: PersonField.system_field("birthday"), profile_mode: :update_profile)
    @consent_form.form_questions.reset

    before = person(:ward).birthday
    assert_match(/\ANot allowed/, assert_nothing_changes { save_answers(:admin, :ward, { birthday => "1990-01-01" }) }.error)
    assert_equal before, person(:ward).reload.birthday
  end

  test "a question once contact stays refused for a minor, and open to an adult" do
    @own_phone.update!(data_type: :string)

    assert_match(/\ANot allowed/, assert_nothing_changes { save_answers(:admin, :ward, { @own_phone => "555" }) }.error)
    assert_nil save_answers(:admin, :alpha_member, { @own_phone => "555" }).error
  end

  test "if the history can't be read, no question can be answered for a minor" do
    without_question_history do
      assert_match(/\ANot allowed/, save_answers(:admin, :ward, { @comment => "x" }).error)
    end
    assert_nil submission_of(@consent_form, :ward)
  end

  test "a blank required contact question blocks a minor's submit without being named, and the rest stays saved" do
    @own_phone.update!(required: true)

    result = save_answers(:guardian, :ward, { @choice => "Red" }, submit: true)

    assert_match(/another required question, which has to be completed on the form's page/, result.error)
    assert_not_includes result.error, "Own phone"
    assert submission_of(@consent_form, :ward).draft?
    assert_equal "Red", submission_of(@consent_form, :ward).answers["choice"]
  end

  test "a contact answer entered on the page stays out of the result, and is submitted with the rest" do
    respond_to_form(@consent_form, :ward, as: :guardian, answers: { "own_phone" => "555-0199" }, submit: false)

    result = save_answers(:guardian, :ward, { @choice => "Red" }, submit: true)

    assert_not_includes result.value.to_json, "555-0199"
    assert_not_includes result.value["questions"].map { |question| question["label"] }, "Own phone"
    assert_equal "555-0199", submission_of(@consent_form, :ward).answers["own_phone"]
  end

  test "the call log masks the answers, on a refusal too" do
    save_answers(:alpha_member, :alpha_member, { @comment => "secret answer" })
    assert_equal Mcp::Tool::MASKED, McpToolCall.where(tool: "save_form_answers").order(:created_at).last.arguments["answers"]

    save_answers(:beta_member, :alpha_member, { @comment => "secret answer" })
    row = McpToolCall.where(tool: "save_form_answers").order(:created_at).last
    assert_not_includes row.arguments.to_json, "secret answer"
    assert_equal Mcp::Tool::MASKED, row.arguments["answers"]
  end

  test "the audit trail and the hooks run as on the page" do
    assert_hook_runs("form_submissions - submitted") { save_answers(:alpha_member, :alpha_member, { @choice => "Red" }, submit: true) }

    version = AuditLog.where(item_type: "FormSubmission").order(:created_at).last
    assert_equal user(:alpha_member).id.to_s, version.whodunnit
  end

  test "needs write scope and writes switched on" do
    assert_equal "Not allowed", save_answers(:alpha_member, :alpha_member, { @comment => "x" }, scopes: "mcp_read").error
    assert_equal "Writes disabled", save_answers(:alpha_member, :alpha_member, { @comment => "x" }, writes_enabled: false).error
  end
end
