# Badges as the badges index lists them (BadgesController#index:
# policy_scope(Badge)), with the holder count the badge card shows: holders in
# policy_scope(Person). Needs the badges feature. Editors of a badge see all
# its holders in get_badge, so that count can be higher than this one.
class Mcp::Tools::ListBadges < Mcp::Tool
  tool_name "list_badges"
  description "Badges you can see, ordered by name, with their type, team and how many holders you can see."
  scope :read
  feature :badges
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
            name: { type: "string" },
            short: { type: "string" },
            badge_type: { type: "string" },
            team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            holder_count: { type: "integer" }
          },
          required: %w[id name short badge_type team holder_count]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    result = list(ctx.policy_scope(Badge).includes(:badge_type, :team).order(:name, :id), limit: limit) { |badge| badge }
    counts = BadgeAssignment.where(badge_id: result[:items].map(&:id), person_id: ctx.policy_scope(Person).select(:id)).group(:badge_id).count

    result.merge(items: result[:items].map do |badge|
      { id: badge.neat_id, name: badge.name, short: badge.short, badge_type: badge.badge_type.name,
        team: badge.team && team_json(badge.team), holder_count: counts[badge.id] || 0 }
    end)
  end
end
