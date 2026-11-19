# A form to fill in and sign, on top of McpWorld and McpFormsWorld (call
# build_mcp_world and build_mcp_forms_world first).
#
#   "Consent" (Alpha, open) asks Alpha: Choice (required select), Comment (text),
#   Agree (acknowledgment), Own phone (phone type), Size (a person field saved to the
#   profile) and Parent consent (signature, guardian_if_minor).
#   ward is 16 with guardian; alpha_member and alpha_manager are adults.
module McpFormResponsesWorld
  def build_mcp_form_responses_world
    person(:ward).update!(birthday: 16.years.ago.to_date)
    person(:alpha_member).update!(birthday: Date.new(1990, 5, 6))
    person(:alpha_manager).update!(birthday: Date.new(1980, 5, 6))

    @size_field = PersonField.create!(name: "Size", data_type: :string, read_permission: "everyone", write_permission: "everyone")
    @consent_form = create_world_form("Consent", @alpha)
    @choice = @consent_form.form_questions.create!(kind: :input, label: "Choice", data_type: :select, choices: %w[ Red Blue ], required: true)
    @comment = @consent_form.form_questions.create!(kind: :input, label: "Comment", data_type: :text)
    @agree = @consent_form.form_questions.create!(kind: :acknowledgment, label: "Agree")
    @own_phone = @consent_form.form_questions.create!(kind: :input, label: "Own phone", data_type: :phone)
    @size = @consent_form.form_questions.create!(kind: :input, label: "Size", person_field: @size_field, profile_mode: :update_profile)
    @signature = @consent_form.form_questions.create!(kind: :signature, label: "Parent consent", signer: :guardian_if_minor, body: "I give permission.")
    @consent_form.form_questions.reset
  end

  def save_answers(viewer, subject, answers, form: @consent_form, **options)
    call_tool("save_form_answers", user: user(viewer), form_id: form.neat_id, person_id: person(subject).neat_id,
      answers: answers.transform_keys(&:neat_id), **options)
  end

  # Signature questions block activation, so a form without one for what doesn't sign.
  def plain_form
    @plain_form ||= create_world_form("Plain", @alpha).tap do |form|
      @plain_pick = form.form_questions.create!(kind: :input, label: "Pick", data_type: :string, required: true)
      form.form_questions.reset
    end
  end

  def submission_of(form, subject)
    form.form_responses.find_by(subject: person(subject))&.form_submissions&.last
  end

  # With the question history unreadable for the duration of the block.
  def without_question_history
    AuditLog.define_singleton_method(:where) { |*| raise ActiveRecord::ConnectionNotEstablished, "audit database down" }
    yield
  ensure
    AuditLog.singleton_class.remove_method(:where)
  end

  # Asserts the block changes no form records and writes no audit rows.
  def assert_nothing_changes
    models = [ FormResponse, FormSubmission, FormSignature, AuditLog ]
    answers = FormSubmission.order(:id).pluck(:id, :answers, :status)
    result = nil
    assert_no_difference(models.map { |model| -> { model.count } }) { result = yield }
    assert_equal answers, FormSubmission.order(:id).pluck(:id, :answers, :status)
    result
  end
end
