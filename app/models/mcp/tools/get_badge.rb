# One badge and its holders. The badge must be in policy_scope(Badge)
# (BadgesController#show), else "Not found"; needs the badges feature.
# Holders are the badge's holders in policy_scope(Person), for everyone (admins
# included, whose scope is every person): what the badge page's People list,
# list_badges and the search_people badge filter show. The "Manage Assignments"
# page also lists holders to anyone BadgePolicy#edit? passes, which is true for
# every viewer on the "...or self" and "has account" permissions, so
# BadgeAssignmentPolicy#index? isn't used here, nor is its Scope (scope.all).
# badge_assignment_id is what remove_badge takes; it's null unless the viewer may
# remove that assignment (the tool's own check, RemoveBadge.removable?).
class Mcp::Tools::GetBadge < Mcp::Tool
  tool_name "get_badge"
  description "A badge you can see: description, type, team and the holders you can see, ordered by last name, " \
    "with the badge assignment ID where you may remove it."
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
      holders: {
        type: "array",
        items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" }, badge_assignment_id: { type: %w[string null] } }, required: %w[id name badge_assignment_id] }
      },
      truncated: { type: "boolean" }
    },
    required: %w[id name short color description badge_type team holder_count holders truncated]
  )

  def call(badge_id:, limit: DEFAULT_LIMIT)
    badge = ctx.find(Badge, badge_id)
    holders = badge.people.where(id: ctx.policy_scope(Person).select(:id))
    holder_count = holders.count
    listed = list(holders.order(:last_name, :first_name, :id), limit: limit) { |person| person }
    assignments = badge.badge_assignments.where(person_id: listed[:items].map(&:id)).includes(:person).index_by(&:person_id)

    {
      id: badge.neat_id,
      name: badge.name,
      short: badge.short,
      color: badge.color,
      description: badge.description,
      badge_type: badge.badge_type.name,
      team: badge.team && team_json(badge.team),
      holder_count: holder_count,
      holders: listed[:items].map do |person|
        assignment = assignments.fetch(person.id)
        person_json(person).merge(badge_assignment_id: Mcp::Tools::RemoveBadge.removable?(ctx, assignment) ? assignment.neat_id : nil)
      end,
      truncated: listed[:truncated]
    }
  end
end
