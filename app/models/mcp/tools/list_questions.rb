# Questions the viewer can see. Mirrors QuestionsController#index (lines 5-8):
# policy_scope(Question), their teams' questions; open only unless asked otherwise (the
# closed_eq default, line 6); newest first; with the author and reply count the index
# shows. The team filter is the index's team_id_eq, offering policy_scope(Team)
# (questions/index line 14). Questions aren't anonymous on the pages, so they aren't here.
class Mcp::Tools::ListQuestions < Mcp::Tool
  tool_name "list_questions"
  description "Questions on your teams, newest first, with who asked and the number of replies. Open ones unless `open` is false, which lists closed ones. " \
    "Optionally only one team's. A team you can't see is \"Not found\"."
  scope :read
  feature :qa
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only this team's questions (tm_ ID)" },
      open: { type: "boolean", description: "true: open questions (the default). false: closed questions" },
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
            asked_by: REF_SCHEMA,
            closed: { type: "boolean" },
            reply_count: { type: "integer" },
            created_at: { type: "string" }
          },
          required: %w[id title team asked_by closed reply_count created_at]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(team_id: nil, open: true, limit: DEFAULT_LIMIT)
    questions = ctx.policy_scope(Question).where(closed: !open)
    questions = questions.where(team_id: ctx.find(Team, team_id).id) if team_id

    list(questions.includes(:team, :person, :replies).order(created_at: :desc, id: :desc), limit: limit) do |question|
      {
        id: question.neat_id,
        title: question.title,
        team: team_json(question.team),
        asked_by: person_json(question.person),
        closed: question.closed == true,
        reply_count: question.replies.size,
        created_at: time_json(question.created_at)
      }
    end
  end
end
