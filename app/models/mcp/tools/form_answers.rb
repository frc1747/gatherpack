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
#
# Snapshots can miss a state: a draft has none until it is submitted, and submitting
# again overwrites the row's own. So for a minor a question is also judged by every
# earlier version of it on this form, from FormQuestion's audit history (removed
# questions included), read once per call and only when a minor's row needs it. A
# question linked by mistake and then corrected therefore stays out for minors for
# good. An earlier link to a field since deleted can't be judged and counts as
# contact. If the history can't be read at all, no question can be judged, so a
# minor's answers come back empty and the failure is logged. Changes that skip the
# audit trail, such as update_columns in a script, leave nothing to judge by.
class Mcp::Tools::FormAnswers < Mcp::Tool
  WITHHELD_DATA_TYPES = %w[phone email].freeze

  tool_name "form_answers"
  description "A form's submitted answers per person (by last name), question by question. Only people whose response you may read, " \
    "and answers you may see; a hidden answer has readable: false and no value. " \
    "Questions linked to the built-in email, phone, address or birthday fields, questions of phone or email type, and questions that were either of those earlier " \
    "are left out for anyone under 18 or with no birthday on file, whoever is asking. " \
    "Other answers may still hold the same details. " \
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
    questions = Mcp.withhold_contact_details?(row.person) ? questions_for_minor(report, row) : report.questions
    {
      person: person_json(row.person),
      submission: { number: submission.number, submitted_at: time_json(submission.submitted_at), form_version: submission.form_version },
      answers: questions.map do |question|
        readable = report.readable?(row, question)
        { question_id: question.neat_id, label: question.label.to_s, readable: readable, answer: readable ? report.answer(row, question) : nil }
      end
    }
  end

  def questions_for_minor(report, row)
    earlier = earlier_contact_keys(report.form)
    return [] if earlier.nil?

    answered_as_contact = contact_snapshot_keys(row.response)
    report.questions.reject { |question| contact_question?(question) || answered_as_contact.include?(question.key) || earlier.include?(question.key) }
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

  # The keys of questions on this form with an earlier version that counted as
  # contact, or nil if the history can't be read. Each version's object is the
  # question before that change, and the question as it is now is judged separately.
  # The form's ID is only inside object, the one way to reach a removed question.
  def earlier_contact_keys(form)
    return @earlier_contact_keys if defined?(@earlier_contact_keys)

    @earlier_contact_keys = begin
      states = AuditLog.where(item_type: "FormQuestion").where("object LIKE ?", "%#{form.id}%").pluck(:object)
        .map { |object| PaperTrail.serializer.load(object) }
      raise ArgumentError, "unreadable question version" unless states.all?(Hash)

      states = states.select { |state| state["form_id"] == form.id }
      fields = PersonField.where(id: states.filter_map { |state| state["person_field_id"] }).index_by(&:id)
      states.select { |state| contact_state?(state, fields) }.map { |state| state.fetch("key") }.to_set
    rescue => e
      Rails.logger.error("[MCP] form_answers can't read question history for form #{form.id} (request #{ctx.request_id}): #{e.class}: #{e.message}")
      nil
    end
  end

  def contact_state?(state, fields)
    field_id = state["person_field_id"]
    return contact?(nil, FormQuestion.data_types.key(state["data_type"]) || state["data_type"]) unless field_id

    field = fields[field_id]
    field.nil? || contact?(field.system_source, field.data_type)
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
