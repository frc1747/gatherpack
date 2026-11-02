# Takes a badge away, as BadgeAssignmentsController#destroy does.
#
# Mirrors: set_badge (line 55, the badge in policy_scope(Badge)), set_badge_assignment
# (line 59, authorize destroy?), destroy (line 48, destroy!). BadgeAssignmentPolicy#destroy?
# is BadgePolicy#update? on the assignment's badge. The page's policy_scope(BadgeAssignment)
# returns every row, so the lookup goes through the parent instead: the assignment's badge
# must be in policy_scope(Badge).
#
# Narrower than the page in two ways. The holder must also be in policy_scope(Person), since
# this result names them. And BadgePolicy#update? passes everyone on a self-service badge
# ("...or self", "has account"), so there a non-admin may only remove their own assignment or
# that of someone they manage, the rule assign_badge has for giving one. get_badge and
# get_person return an assignment's ID only when removable? says this tool would accept it.
class Mcp::Tools::RemoveBadge < Mcp::Tool
  def self.removable?(ctx, assignment)
    ctx.allowed?(assignment, :destroy?) && Mcp::Tools::AssignBadge.may_choose?(ctx, assignment.badge, assignment.person)
  end

  tool_name "remove_badge"
  description "Take a badge away from a person, by the badge assignment's ID. " \
    "On a badge open to self-service, you can remove only your own or that of people you manage, unless you're an admin. Returns what was removed."
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
    raise Mcp::NotAllowed unless self.class.removable?(ctx, assignment)

    assignment.destroy!

    changed!(assignment)
    { id: assignment.neat_id, person: person_json(assignment.person), badge: { id: assignment.badge.neat_id, name: assignment.badge.name }, removed: true }
  end
end
