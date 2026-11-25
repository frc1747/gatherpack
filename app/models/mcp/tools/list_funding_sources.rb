# Funding sources, as Purchasing → Funding sources lists them
# (Orders::FundingSourcesController#index: policy_scope(FundingSource), in use first, by name).
# Anyone signed in sees a source's name, team, kind, dates and restriction; its amount, spent,
# committed and remaining only where FundingSourcePolicy#numbers? allows (funding managers,
# admins, and approvers of a team that can use it), and its giver, reference and report due date
# only where restricted_fields? does, as the source's page. Needs the orders feature.
class Mcp::Tools::ListFundingSources < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "list_funding_sources"
  description "Funding sources (budgets and restricted gifts), in use first, with team, kind, dates and restriction. Funding " \
    "managers, admins and approvers who can use a source also see its amount, spent, committed and remaining."
  scope :read
  feature :orders
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only sources this team can use: its own and those of teams above it (tm_)" },
      include_inactive: { type: "boolean", description: "Also list sources no longer in use (default true, as the page)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::OrderRecords::FUNDING_SOURCE_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(team_id: nil, include_inactive: true, limit: DEFAULT_LIMIT)
    sources = ctx.policy_scope(FundingSource).includes(:team).order(active: :desc, name: :asc, id: :asc)
    sources = sources.where(active: true) unless include_inactive
    if team_id
      team = ctx.find(Team, team_id)
      sources = sources.where(id: sources.select { |source| source.usable_by?(team) }.map(&:id))
    end
    list(sources, limit: limit) { |source| funding_source_json(source) }
  end
end
