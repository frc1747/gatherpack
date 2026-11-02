# A form's submitted answers per person, as the results page shows them
# (FormsController#results, active versions). Gate: FormPolicy#results?. People
# are FormReport's rows for the viewer (Form#readable_subjects_for), and each
# response must also pass FormResponsePolicy#show? (the response page's gate).
# Per answer, FormReport#readable? decides, as the results page does for each
# cell: FormAccess#question_readable?, i.e. the question's own read level inside
# the form's, and for a question linked to a person field that field's levels
# (PersonFieldAccess#readable?, the same as the field's readable_by?). An answer
# the viewer may not see comes back with readable: false and no value, the
# page's "·". Only the active submission is read, never an unsubmitted update,
# and signatures and "profile changed" notes are left out. Differs from the page
# in nothing else; person_id narrows to one person, who must be among the people the viewer may read on this form
# (Form#readable_subjects_for, not policy_scope(Person): a read grant reaches
# people outside the viewer's teams), else "Not found". Rows are in the page's
# order with same-named people ordered by ID, and the per-response check runs
# only until the limit is passed.
#
# Narrower than the page for a minor (Mcp.withhold_contact_details?), whoever the
# viewer is: answers to contact questions are left out of that person's list, with
# no per-person reason. The person judged is the response's subject, whoever filled
# it in, and each row is judged alone. A contact question is linked to built-in
# email, phone number, address or birthday (by system_source, not key: the phone
# field's key is "phone"), or has the phone or email type, its person field's type
# if it has one. Those are the only types that say what an answer holds: a date
# may be any date, and an address is free text, so those and other free-text
# answers can't be judged and stay. A question is judged as it is now and as it was
# in the snapshot (content["questions"]) of each of the response's submissions,
# current or earlier: answers are stored by key, a question can be unlinked,
# relinked, or removed and added back after it was answered, and a new submission
# starts from the last one's answers. So a value entered again under a question
# that is now plain stays out too, failing closed. A submission with no snapshot
# adds nothing to judge by. FormReport preloads the submissions.
class Mcp::Tools::FormAnswers < Mcp::Tool
  WITHHELD_DATA_TYPES = %w[phone email].freeze

  tool_name "form_answers"
  description "A form's submitted answers per person (by last name), question by question. Only people whose response you may read, " \
    "and answers you may see; a hidden answer has readable: false and no value. " \
    "Questions linked to the built-in email, phone, address or birthday fields, and questions of phone or email type, are left out for anyone under 18 or with no birthday on file, whoever is asking. " \
    "Other answers are returned as given and may hold the same details. " \
    "Optionally only one person."
  scope :read
  feature :forms
  input_schema(
    properties: {
      form_id: { type: "string", description: "The form (frm_ ID)" },
      person_id: { type: "string", description: "Only this person's answers (per_ ID)" },
      limit: limit_property
    },
    required: %w[form_id]
  )
  output_schema(
    type: "object",
    properties: {
      form: {
        type: "object",
        properties: { id: { type: "string" }, title: { type: "string" } },
        required: %w[id title]
      },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            person: REF_SCHEMA,
            submission: {
              type: "object",
              properties: {
                number: { type: "integer" },
                submitted_at: { type: [ "string", "null" ] },
                form_version: { type: "integer" }
              },
              required: %w[number submitted_at form_version]
            },
            answers: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  question_id: { type: "string" },
                  label: { type: "string" },
                  readable: { type: "boolean" },
                  answer: { description: "The answer, or null when unanswered or not readable" }
                },
                required: %w[question_id label readable answer]
              }
            }
          },
          required: %w[person submission answers]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[form items truncated]
  )

  def call(form_id:, person_id: nil, limit: DEFAULT_LIMIT)
    form = ctx.find(Form.all, form_id)
    ctx.authorize!(form, :results?)
    only = person_id && [ ctx.find(form.readable_subjects_for(ctx.person), person_id).id ]

    report = FormReport.new(form, viewer: ctx.person, only: only)
    limit = limit.to_i.clamp(1, MAX_LIMIT)
    rows = in_stable_order(report.rows).lazy.select { |row| row.submission && ctx.allowed?(row.response, :show?) }.first(limit + 1)

    {
      form: { id: form.neat_id, title: form.title },
      items: rows.first(limit).map { |row| row_json(report, row) },
      truncated: rows.size > limit
    }
  end

  private

  # FormReport's order, with people of the same name ordered by ID.
  def in_stable_order(rows)
    rows.chunk_while { |a, b| a.person.last_name == b.person.last_name && a.person.first_name == b.person.first_name }
      .flat_map { |same| same.sort_by { |row| row.person.id } }
  end

  def row_json(report, row)
    submission = row.submission
    questions = report.questions
    if Mcp.withhold_contact_details?(row.person)
      answered_as_contact = contact_snapshot_keys(row.response)
      questions = questions.reject { |question| contact_question?(question) || answered_as_contact.include?(question.key) }
    end
    {
      person: person_json(row.person),
      submission: { number: submission.number, submitted_at: time_json(submission.submitted_at), form_version: submission.form_version },
      answers: questions.map do |question|
        readable = report.readable?(row, question)
        { question_id: question.neat_id, label: question.label.to_s, readable: readable, answer: readable ? report.answer(row, question) : nil }
      end
    }
  end

  def contact_question?(question)
    contact?(question.person_field&.system_source, question.value_type.data_type)
  end

  # The keys of questions that counted as contact in any of this response's submissions.
  def contact_snapshot_keys(response)
    response.form_submissions.flat_map { |submission| Array(submission.content["questions"]) }
      .select { |snapshot| contact?(system_sources[snapshot["person_field"]], snapshot["type"]) }
      .map { |snapshot| snapshot["key"] }.to_set
  end

  # Built-in fields by key, archived ones too, for reading snapshots. Built-in
  # fields can't be deleted, and a key missing here is a custom field or none.
  def system_sources
    @system_sources ||= PersonField.system.pluck(:key, :system_source).to_h
  end

  def contact?(source, data_type)
    return true if source && Mcp::MinorRule::WITHHELD_KEYS.include?(source.delete_prefix("user."))

    WITHHELD_DATA_TYPES.include?(data_type)
  end
end
