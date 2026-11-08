# One question and its replies. Mirrors QuestionsController#show (lines 12-16) through
# set_question (line 72): policy_scope(Question). The authorize there is show?, which
# QuestionPolicy doesn't define, so the scope is what decides. Replies come as the page
# lists them (questions/show, replies/_reply): top-level ones oldest first, each followed
# by its children, oldest first. parent_id says which is which. promoted marks the "Top
# Replies" (promoted_replies, limit 3). Nothing is anonymous or hidden on the page, and
# vote counts aren't shown there, so they aren't here; the viewer's own vote is.
class Mcp::Tools::GetQuestion < Mcp::Tool
  tool_name "get_question"
  description "One question on your teams, with its replies in page order (parent_id for replies to replies). A question you can't see is \"Not found\"."
  scope :read
  feature :qa
  input_schema(
    properties: { question_id: { type: "string", description: "The question's ID (qst_)" } },
    required: [ "question_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      content: { type: "string" },
      team: REF_SCHEMA,
      asked_by: REF_SCHEMA,
      closed: { type: "boolean" },
      created_at: { type: "string" },
      voted_reply_id: { type: %w[string null] },
      replies: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            parent_id: { type: %w[string null] },
            person: REF_SCHEMA,
            content: { type: "string" },
            promoted: { type: "boolean" },
            created_at: { type: "string" }
          },
          required: %w[id parent_id person content promoted created_at]
        }
      }
    },
    required: %w[id title content team asked_by closed created_at voted_reply_id replies]
  )

  def call(question_id:)
    question = ctx.find(Question, question_id)
    promoted_ids = question.promoted_replies(limit: 3).map(&:id)

    {
      id: question.neat_id,
      title: question.title,
      content: question.content,
      team: team_json(question.team),
      asked_by: person_json(question.person),
      closed: question.closed == true,
      created_at: time_json(question.created_at),
      voted_reply_id: question.voted_reply_for(ctx.person)&.neat_id,
      replies: question.replies.top_level.includes(:person).order(created_at: :asc).flat_map { |reply| reply_thread(reply, promoted_ids) }
    }
  end

  private

  def reply_thread(reply, promoted_ids)
    children = reply.children.includes(:person).order(created_at: :asc).flat_map { |child| reply_thread(child, promoted_ids) }
    [ reply_json(reply, promoted_ids), *children ]
  end

  def reply_json(reply, promoted_ids)
    {
      id: reply.neat_id,
      parent_id: reply.parent&.neat_id,
      person: person_json(reply.person),
      content: reply.content,
      promoted: promoted_ids.include?(reply.id),
      created_at: time_json(reply.created_at)
    }
  end
end
