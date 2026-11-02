# Takes a badge away, as BadgeAssignmentsController#destroy does.
#
# Mirrors: set_badge (line 55, the badge in policy_scope(Badge)), set_badge_assignment
# (line 59, authorize destroy?), destroy (line 48, destroy!). BadgeAssignmentPolicy#destroy?
# is BadgePolicy#update? on the assignment's badge. The page's policy_scope(BadgeAssignment)
# returns every row, so the lookup goes through the parent instead: the assignment's badge
# must be in policy_scope(Badge).
#
# Narrower than the page in one way: the holder must also be in policy_scope(Person), since
# this result names them. Like the page, "...or self" and "has account" badges pass
# BadgePolicy#update? for everyone, so a viewer can remove those from anyone they can see.
class Mcp::Tools::RemoveBadge < Mcp::Tool
  tool_name "remove_badge"
  description "Take a badge away from a person, by the badge assignment's ID. Returns what was removed."
  scope :write
  feature :badges
  destructive
  input_schema(
    properties: { badge_assignment_id: { type: "string", description: "The badge assignment's ID (bda_)" } },
    required: [ "badge_assignment_id" ]
  )
  output_schema(
    type: "object",
    properties: { id: { type: "string" }, person: REF_SCHEMA, badge: REF_SCHEMA, removed: { type: "boolean" } },
    required: %w[id person badge removed]
  )

  def call(badge_assignment_id:)
    visible = BadgeAssignment.where(badge_id: ctx.policy_scope(Badge).select(:id), person_id: ctx.policy_scope(Person).select(:id))
    assignment = ctx.find(visible, badge_assignment_id)
    ctx.authorize!(assignment, :destroy?)
    assignment.destroy!

    changed!(assignment)
    { id: assignment.neat_id, person: person_json(assignment.person), badge: { id: assignment.badge.neat_id, name: assignment.badge.name }, removed: true }
  end
end
