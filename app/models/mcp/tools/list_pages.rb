# The pages the viewer can open. Mirrors the index's policy_scope(Page)
# (PagesController#index, line 6), narrowed by PagePolicy#show?, the check on the show
# action (set_page, line 53), since the index also lists pages that won't open for this
# viewer. PagePolicy::Scope's team_id: "" matches nothing, so a team-less page reaches a
# non-admin only if its viewer level is public or user. No content or preview, which the
# index shows even for a page it won't open.
class Mcp::Tools::ListPages < Mcp::Tool
  tool_name "list_pages"
  description "The pages you can open, by title, with team and whether they're dynamic. A page you can't open isn't listed."
  scope :read
  feature :pages
  input_schema(properties: { limit: limit_property })
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
            team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            dynamic: { type: "boolean" }
          },
          required: %w[id title team dynamic]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    limit = limit.to_i.clamp(1, MAX_LIMIT)
    # show? is a per-record rule, and this doesn't load the content it won't return.
    pages = ctx.policy_scope(Page).select(:id, :title, :team_id, :viewer, :dynamic).includes(:team).order(:title, :id)
    openable = pages.lazy.select { |page| ctx.allowed?(page, :show?) }.first(limit + 1)

    {
      items: openable.first(limit).map { |page| { id: page.neat_id, title: page.title, team: page.team && team_json(page.team), dynamic: page.dynamic == true } },
      truncated: openable.size > limit
    }
  end
end
