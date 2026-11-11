# What get_form and the form response writes share: finding a response the way
# FormResponsesController#set_response does (form_responses_controller.rb:96-100),
# their refusals, and the result they all return.
#
# The person is found among all people, as the page does, because a form's own levels
# decide who is reachable: a read grant reaches people outside the viewer's teams.
#
# A minor's contact questions (Mcp::FormContactQuestions) are left out of the result,
# answers included, and can't be answered here, whoever is asking, with no reason given
# per person.
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
      can_sign: { type: "boolean", description: "Whether you may give this signature (only with person_id)" },
      answer: { description: "The answer in the unsubmitted or unsigned version if there is one, else the one in effect; null when unanswered (only with person_id, and only on what can be answered)" }
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
          closes_at: { type: [ "string", "null" ] },
          expires_on: { type: [ "string", "null" ], description: "Responses stop counting from this date (YYYY-MM-DD); only for those who may edit the form's details" },
          valid_for_months: { type: [ "integer", "null" ], description: "Responses stop counting this many months after each is signed; only for those who may edit the form's details" }
        },
        required: %w[id title description status closes_at expires_on valid_for_months]
      },
      questions: { type: "array", items: QUESTION_SCHEMA },
      response: {
        type: [ "object", "null" ],
        description: "The person's response; null without person_id",
        properties: {
          person: Mcp::Tool::REF_SCHEMA,
          status: { type: "string", description: "not_started, draft, waiting (submitted, waiting for an answer or a signature), complete, needs_reconfirmation (also once its expiry has passed) or withdrawn" },
          expires_at: { type: [ "string", "null" ], description: "When the response in effect stops counting; null if the form's responses don't expire or none is in effect" },
          asked: { type: "boolean", description: "False when the form no longer asks this person" },
          update_in_progress: { type: "boolean", description: "An unsubmitted update exists while earlier answers stay in effect" },
          submitted_at: { type: [ "string", "null" ] },
          waiting_for: { type: "array", items: { type: "string" } },
          not_copied_to_profile: { type: "array", items: { type: "string" }, description: "Questions whose answer in effect couldn't be saved to the profile" },
          can_update: { type: "boolean", description: "Whether you may answer or submit: false on a form that leaves every question to someone else" },
          can_withdraw: { type: "boolean" },
          can_sign: { type: "boolean" }
        },
        required: %w[person status expires_at asked update_in_progress submitted_at waiting_for not_copied_to_profile can_update can_withdraw can_sign]
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

  # Whether the fill page offers Save and Submit (edit.html.erb:6 and :105): the viewer
  # can write a question, or the form has none to answer. Counted before the minor rule,
  # as the page counts them.
  def fill_page_offers_submit?(response)
    questions = response.form.answerable_questions
    access = access_for(response)
    questions.empty? || questions.any? { |question| access.question_writable?(question) }
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
      .merge(expiry_json(form))
  end

  # The expiry rule is on the form's details screen (forms/_details_fields), which
  # FormPolicy#update? opens; others see its effect on their response (expires_at).
  def expiry_json(form)
    return { expires_on: nil, valid_for_months: nil } unless ctx.allowed?(form, :update?)

    { expires_on: date_json(form.expires_on), valid_for_months: form.valid_for_months }
  end

  # With a response, the questions the fill page shows (edit.html.erb): those that
  # aren't answers, and the answerable ones the viewer may read, each with its answer.
  # The response page's History shows anyone who may read the response its draft or
  # pending version (show.html.erb, _answers.html.erb), question by question, so the
  # open version is read for all of them.
  def questions_json(form, response)
    return listed_questions_json(form) unless response

    access = access_for(response)
    open = open_questions(response)
    submission = response.open_submission || response.active_submission
    form.form_questions.includes(:person_field).filter_map do |question|
      next if question.answerable? && !(open.include?(question) && access.question_readable?(question))

      json = question_json(question).merge(writable: access.question_writable?(question), signed: !!submission&.signature_for(question), can_sign: access.can_sign?(question))
      question.answerable? ? json.merge(answer: submission&.answer(question)) : json
    end
  end

  # Without a person, every question: the results and totals pages show each one's
  # label and options. An answerable question's help text shows only on the form's
  # editor (FormPolicy#update?) and the fill page, so the rest get it only for a
  # question they may read for someone, by the results page's check on each cell.
  def listed_questions_json(form)
    readers = FormReport.new(form, viewer: ctx.person).rows.map(&:access) unless ctx.allowed?(form, :update?)
    form.form_questions.includes(:person_field).map do |question|
      hidden = readers && question.answerable? && readers.none? { |access| access.question_readable?(question) }
      hidden ? question_json(question).merge(body: nil) : question_json(question)
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
      expires_at: time_json(response.expires_at),
      asked: response.form.in_audience?(response.subject),
      update_in_progress: response.update_in_progress?,
      submitted_at: time_json(open&.pending? ? open.submitted_at : active&.submitted_at),
      waiting_for: open&.pending? ? waiting_for(response, open) : [],
      not_copied_to_profile: not_copied_to_profile(response, active),
      can_update: ctx.allowed?(response, :update?) && fill_page_offers_submit?(response),
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

  # What a write can change besides its submission, read before it for also_changed.
  def side_state(response)
    { signature_ids: FormSignature.standing.where(form_submission_id: response.form_submissions.map(&:id)).ids, badge: completion_assignment(response) }
  end

  # The signatures revoked since side_state, and the completion badge's assignment if
  # sync_status! granted or removed it.
  def also_changed(response, before)
    badge = completion_assignment(response)
    FormSignature.where(id: before[:signature_ids]).reject(&:standing?) + (badge == before[:badge] ? [] : [ badge || before[:badge] ])
  end

  def completion_assignment(response)
    badge = response.form.completion_badge
    badge && BadgeAssignment.find_by(badge: badge, person: response.subject)
  end
end
