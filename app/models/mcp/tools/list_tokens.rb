# A person's tokens, as their profile lists them (PeopleController#show line 15):
# set_person (line 103, in policy_scope(Person), then show?) and policy_scope(person.tokens),
# so admins see all, managers those of their teams' people and their own, everyone else
# their own. Values are never returned in full, to anyone: see Mcp::TokenRecords. Oldest
# first rather than the page's by-value order, since the order would hint at the value.
class Mcp::Tools::ListTokens < Mcp::Tool
  include Mcp::TokenRecords

  tool_name "list_tokens"
  description "A person's scan cards and tags, as their profile lists them. Values are always masked (first two and last two characters, length), for everyone. Someone you can see but whose tokens you can't comes back empty; someone you can't see is \"Not found\"."
  scope :read
  feature :tokens
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      limit: limit_property
    },
    required: %w[person_id]
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::TokenRecords::SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(person_id:, limit: DEFAULT_LIMIT)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :show?)

    list(ctx.policy_scope(person.tokens).includes(:tokenable).order(:created_at, :id), limit: limit) { |token| token_json(token) }
  end
end
