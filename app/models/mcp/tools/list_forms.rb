# Forms as the forms index lists them (FormsController#index), not archived
# ones: the forms in policy_scope(Form) (the viewer's managed forms, which
# also holds their drafts); open and closed forms the viewer or one of their
# wards may read a response to (FormResponsePolicy#show?, the index's own "My
# Forms" entries, so a closed form needs a response from that person); and
# open and closed forms the viewer can show (FormPolicy#show?, "Shared with
# You"). The counts are the viewer's to see only for a form they manage
# (FormPolicy#manage?): assigned is everyone the form asks, submitted those
# with an answer in effect (an active submission). For any other form counts is
# null, so the tool never says more than the page does. can_see_results says
# whether form_status and form_answers will work for the form
# (FormPolicy#results?). status defaults to all.
class Mcp::Tools::ListForms < Mcp::Tool
  STATUSES = %w[open closed all].freeze

  tool_name "list_forms"
  description "Forms you can see, open ones first then by title, with team, status and deadline. Forms you manage also show " \
    "how many people are asked (assigned) and how many have an answer in effect (submitted). " \
    "`status` is open, closed or all (default all; drafts only show for forms you manage)."
  scope :read
  feature :forms
  input_schema(
    properties: {
      status: { type: "string", enum: STATUSES, description: "open, closed or all (default all)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            title: { type: "string" },
            team: REF_SCHEMA,
            status: { type: "string" },
            opens_at: { type: [ "string", "null" ] },
            closes_at: { type: [ "string", "null" ] },
            can_see_results: { type: "boolean" },
            counts: {
              anyOf: [
                { type: "null" },
                {
                  type: "object",
                  properties: { assigned: { type: "integer" }, submitted: { type: "integer" } },
                  required: %w[assigned submitted]
                }
              ]
            }
          },
          required: %w[id title team status opens_at closes_at can_see_results counts]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(status: "all", limit: DEFAULT_LIMIT)
    forms = Form.where(id: visible_form_ids).includes(:team)
    forms = forms.where(status: status) unless status == "all"

    list(forms.order(Arel.sql("forms.status = 1 DESC"), :title, :id), limit: limit) { |form| form_json(form) }
  end

  private

  def form_json(form)
    {
      id: form.neat_id,
      title: form.title,
      team: team_json(form.team),
      status: form.status,
      opens_at: time_json(form.opens_at),
      closes_at: time_json(form.closes_at),
      can_see_results: ctx.allowed?(form, :results?),
      counts: ctx.allowed?(form, :manage?) ? counts(form) : nil
    }
  end

  def counts(form)
    asked = form.audience.select(:id)
    {
      assigned: form.audience.count,
      submitted: form.form_responses.where(subject_id: asked).where.not(active_submission_id: nil).count
    }
  end

  def visible_form_ids
    managed = ctx.policy_scope(Form).visible.ids
    others = Form.where(status: %i[open closed]).where.not(id: managed).select { |form| shared?(form) || mine?(form) }
    managed + others.map(&:id)
  end

  def shared?(form)
    ctx.allowed?(form, :show?)
  end

  # The viewer, or a ward, can read a response to the form; a closed form
  # only counts once that person has one.
  def mine?(form)
    subjects.any? do |subject|
      next false if form.closed? && !responded.include?([ form.id, subject.id ])

      ctx.allowed?(FormResponse.new(form: form, subject: subject), :show?)
    end
  end

  def subjects
    @subjects ||= [ ctx.person ] + ctx.person.wards.to_a
  end

  def responded
    @responded ||= FormResponse.where(subject_id: subjects.map(&:id)).pluck(:form_id, :subject_id).to_set
  end
end
