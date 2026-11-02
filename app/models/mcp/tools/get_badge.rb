# One badge and its holders. The badge must be in policy_scope(Badge)
# (BadgesController#show), else "Not found"; needs the badges feature.
# Holders are the badge's holders in policy_scope(Person), for everyone (admins
# included, whose scope is every person): what the badge page's People list,
# list_badges and the search_people badge filter show. The "Manage Assignments"
# page also lists holders to anyone BadgePolicy#edit? passes, which is true for
# every viewer on the "...or self" and "has account" permissions, so
# BadgeAssignmentPolicy#index? isn't used here, nor is its Scope (scope.all).
class Mcp::Tools::GetBadge < Mcp::Tool
  tool_name "get_badge"
  description "A badge you can see: description, type, team and the holders you can see, ordered by last name."
  scope :read
  feature :badges
  input_schema(
    properties: { badge_id: { type: "string", description: "Badge ID (bdg_...)" }, limit: limit_property },
    required: [ "badge_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      short: { type: "string" },
      color: { type: "string" },
      description: { type: %w[string null] },
      badge_type: { type: "string" },
      team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
      holder_count: { type: "integer" },
      holders: { type: "array", items: REF_SCHEMA },
      truncated: { type: "boolean" }
    },
    required: %w[id name short color description badge_type team holder_count holders truncated]
  )

  def call(badge_id:, limit: DEFAULT_LIMIT)
    badge = ctx.find(Badge, badge_id)
    holders = badge.people.where(id: ctx.policy_scope(Person).select(:id))
    holder_count = holders.count
    listed = list(holders.order(:last_name, :first_name, :id), limit: limit) { |person| person_json(person) }

    {
      id: badge.neat_id,
      name: badge.name,
      short: badge.short,
      color: badge.color,
      description: badge.description,
      badge_type: badge.badge_type.name,
      team: badge.team && team_json(badge.team),
      holder_count: holder_count,
      holders: listed[:items],
      truncated: listed[:truncated]
    }
  end
end
