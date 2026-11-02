# One badge and its holders. The badge must be in policy_scope(Badge)
# (BadgesController#show), else "Not found"; needs the badges feature.
# Holders follow the "Manage Assignments" page: when
# BadgeAssignmentPolicy#index? allows the viewer (they can edit the badge,
# BadgePolicy#edit?) all holders; otherwise only holders in policy_scope(Person)
# (what the badge page lists). BadgeAssignmentPolicy::Scope is scope.all and
# is not used. Note BadgePolicy#update? is true for the "...or self" and
# "has account" permissions, so those badges show all holders to everyone.
class Mcp::Tools::GetBadge < Mcp::Tool
  tool_name "get_badge"
  description "A badge you can see: description, type, team and its holders (all of them if you can manage the badge, " \
    "otherwise the holders you can see), ordered by last name."
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
    holders = badge.people
    holders = holders.where(id: ctx.policy_scope(Person).select(:id)) unless ctx.allowed?(badge, :index?, policy_class: BadgeAssignmentPolicy)
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
