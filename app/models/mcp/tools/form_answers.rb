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
# in nothing else; person_id narrows to one person, who must be in
# policy_scope(Person) and, if the viewer can't read their response, simply
# has no items.
class Mcp::Tools::FormAnswers < Mcp::Tool
  tool_name "form_answers"
  description "A form's submitted answers per person (by last name), question by question. Only people whose response you may read, " \
    "and answers you may see; a hidden answer has readable: false and no value. Optionally only one person."
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
    only = person_id && [ ctx.find(Person, person_id).id ]

    report = FormReport.new(form, viewer: ctx.person, only: only)
    rows = report.rows.select { |row| row.submission && ctx.allowed?(row.response, :show?) }
    limit = limit.to_i.clamp(1, MAX_LIMIT)

    {
      form: { id: form.neat_id, title: form.title },
      items: rows.first(limit).map { |row| row_json(report, row) },
      truncated: rows.size > limit
    }
  end

  private

  def row_json(report, row)
    submission = row.submission
    {
      person: person_json(row.person),
      submission: { number: submission.number, submitted_at: time_json(submission.submitted_at), form_version: submission.form_version },
      answers: report.questions.map do |question|
        readable = report.readable?(row, question)
        { question_id: question.neat_id, label: question.label.to_s, readable: readable, answer: readable ? report.answer(row, question) : nil }
      end
    }
  end
end
