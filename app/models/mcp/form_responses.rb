# What get_form and the form response writes share: finding a response the way
# FormResponsesController#set_response does (form_responses_controller.rb:96-100),
# their refusals, and the result they all return.
#
# The person is found among all people, as the page does, because a form's own levels
# decide who is reachable: a read grant reaches people outside the viewer's teams.
#
# A minor's contact questions (Mcp::FormContactQuestions) are left out of the result
# and can't be answered here, whoever is asking, with no reason given per person.
module Mcp::FormResponses
  include Mcp::FormContactQuestions

  QUESTION_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      kind: { type: "string", description: "input, acknowledgment (a yes/no that must be ticked when required), intent, heading, statement or signature" },
      label: { type: [ "string", "null" ] },
      body: { type: [ "string", "null" ] },
      required: { type: "boolean" },
      type: { type: [ "string", "null" ], description: "How to answer: string, text, boolean, date (YYYY-MM-DD), integer, select, multi_select, phone or email; null for what isn't answered" },
      options: { type: "array", items: { type: "string" }, description: "The choices of a select or multi_select" },
      hint: { type: [ "string", "null" ], description: "The format a string answer must follow, or the range of a number or date" },
      saves_to_profile: { type: "boolean", description: "Submitting also saves the answer to the person's profile field" },
      signer: { type: [ "string", "null" ], description: "Who signs a signature question, in words" },
      writable: { type: "boolean", description: "Whether you may answer this for the person (only with person_id)" },
      signed: { type: "boolean", description: "Whether this version has this signature (only with person_id)" },
      can_sign: { type: "boolean", description: "Whether you may give this signature (only with person_id)" }
    },
    required: %w[id kind label body required type options hint saves_to_profile signer]
  }.freeze

  OUTPUT_SCHEMA = {
    type: "object",
    properties: {
      form: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          description: { type: [ "string", "null" ] },
          status: { type: "string" },
          closes_at: { type: [ "string", "null" ] }
        },
        required: %w[id title description status closes_at]
      },
      questions: { type: "array", items: QUESTION_SCHEMA },
      response: {
        type: [ "object", "null" ],
        description: "The person's response; null without person_id",
        properties: {
          person: Mcp::Tool::REF_SCHEMA,
          status: { type: "string", description: "not_started, draft, waiting (submitted, waiting for an answer or a signature), complete, needs_reconfirmation or withdrawn" },
          asked: { type: "boolean", description: "False when the form no longer asks this person" },
          update_in_progress: { type: "boolean", description: "An unsubmitted update exists while earlier answers stay in effect" },
          submitted_at: { type: [ "string", "null" ] },
          waiting_for: { type: "array", items: { type: "string" } },
          not_copied_to_profile: { type: "array", items: { type: "string" }, description: "Questions whose answer in effect couldn't be saved to the profile" },
          can_update: { type: "boolean" },
          can_withdraw: { type: "boolean" },
          can_sign: { type: "boolean" }
        },
        required: %w[person status asked update_in_progress submitted_at waiting_for not_copied_to_profile can_update can_withdraw can_sign]
      }
    },
    required: %w[form questions response]
  }.freeze

  private

  def find_form(form_id)
    ctx.find(Form.all, form_id)
  end

  def find_response(form, person_id)
    subject = ctx.find(Person.all, person_id)
    form.form_responses.includes(:form_submissions).find_or_initialize_by(subject: subject)
  end

  # "Not found" if the viewer can't read this response, "Not allowed" if they can.
  def authorize_response!(response, query)
    return if ctx.allowed?(response, query)

    ctx.allowed?(response, :show?) ? raise(Mcp::NotAllowed) : not_found!
  end

  def access_for(response)
    FormAccess.new(ctx.person, response.subject, response.form)
  end

  # What a tool may show or take for this person, among answerable questions.
  def open_questions(response)
    questions = response.form.answerable_questions
    Mcp.withhold_contact_details?(response.subject) ? questions_open_for_minor(questions, response.form, response) : questions
  end

  # The form with its questions, in the read tool's shape. Reads the response again:
  # a write may have just changed it, and its person's birthday.
  def form_json(form, response = nil)
    response = form.form_responses.includes(:form_submissions).find_or_initialize_by(subject: Person.find(response.subject_id)) if response
    { form: form_details_json(form), questions: questions_json(form, response), response: response && response_json(response) }
  end

  def form_details_json(form)
    { id: form.neat_id, title: form.title, description: form.description, status: form.status, closes_at: time_json(form.closes_at) }
  end

  # With a response, the questions the fill page shows (edit.html.erb): those that
  # aren't answers, and the answerable ones the viewer may read.
  def questions_json(form, response)
    return form.form_questions.includes(:person_field).map { |question| question_json(question) } unless response

    access = access_for(response)
    open = open_questions(response)
    submission = response.open_submission || response.active_submission
    form.form_questions.includes(:person_field).filter_map do |question|
      next if question.answerable? && !(open.include?(question) && access.question_readable?(question))

      question_json(question).merge(writable: access.question_writable?(question), signed: !!submission&.signature_for(question), can_sign: access.can_sign?(question))
    end
  end

  def question_json(question)
    answerable = question.answerable?
    type = question.value_type
    {
      id: question.neat_id, kind: question.kind, label: question.label, body: question.body, required: question.required?,
      type: answerable ? type.data_type : nil,
      options: answerable && %w[select multi_select].include?(type.data_type) ? type.choice_list : [],
      hint: answerable ? answer_hint(type) : nil,
      saves_to_profile: question.update_profile?,
      signer: question.signature? ? question.signer_description : nil
    }
  end

  def answer_hint(type)
    case type.data_type
    when "string" then type.pattern_hint.presence
    when "integer", "date" then [ type.min, type.max ].any?(&:present?) ? "from #{type.min.presence || "any"} to #{type.max.presence || "any"}" : nil
    end
  end

  def response_json(response)
    open = response.open_submission
    active = response.active_submission
    {
      person: person_json(response.subject),
      status: response.persisted? ? response.status : "not_started",
      asked: response.form.in_audience?(response.subject),
      update_in_progress: response.update_in_progress?,
      submitted_at: time_json(open&.pending? ? open.submitted_at : active&.submitted_at),
      waiting_for: open&.pending? ? waiting_for(response, open) : [],
      not_copied_to_profile: not_copied_to_profile(response, active),
      can_update: ctx.allowed?(response, :update?),
      can_withdraw: ctx.allowed?(response, :withdraw?),
      can_sign: ctx.allowed?(response, :sign?)
    }
  end

  # FormSubmission#waiting_for, without naming a question withheld for this person.
  def waiting_for(response, submission)
    open = open_questions(response)
    missing, withheld = submission.missing_questions.partition { |question| open.include?(question) }
    missing.map { |question| "an answer to #{question.label}" } +
      (withheld.any? ? [ "another required answer" ] : []) +
      submission.missing_signatures.map { |question| "#{question.signer_description}'s signature (#{question.label})" }
  end

  # The page's "Not copied to profile" badge (_answers.html.erb), on what the viewer may read.
  def not_copied_to_profile(response, active)
    return [] unless active

    access = access_for(response)
    open_questions(response).select { |question| active.profile_skipped.include?(question.key) && access.question_readable?(question) }.map(&:label)
  end

  # The records an activation changed along with the submission: the person, when an
  # answer was saved to their profile.
  def profile_records(submission)
    return [] unless submission.active? && submission.form.answerable_questions.any? { |question| question.update_profile? && submission.profile_skipped.exclude?(question.key) }

    [ submission.subject ]
  end
end
