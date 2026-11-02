# Gives a person a badge, as BadgeAssignmentsController#create does.
#
# Mirrors: set_badge (line 55, the badge in policy_scope(Badge)), create (lines
# 28-30: build through the badge, authorize create?, save). BadgeAssignmentPolicy#create?
# is BadgePolicy#update?, so the badge's permission decides who may grant it, the
# viewer's own grant included: a member can't give themselves an "added by admin"
# or "added by manager" badge. The model's team badge membership and duplicate
# validations come back as invalid-argument errors.
#
# Narrower than the page in one way: the person must be in policy_scope(Person).
# The POST doesn't check the person, but its form only offers people the viewer can
# see, and this result names them. Like the page, "...or self" and "has account"
# badges pass BadgePolicy#update? for everyone, so a viewer can give those to anyone
# they can see, not only to themselves.
class Mcp::Tools::AssignBadge < Mcp::Tool
  tool_name "assign_badge"
  description "Give a person a badge. Team badges need the person on the badge's team. Returns the new assignment."
  scope :write
  feature :badges
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      badge_id: { type: "string", description: "The badge's ID (bdg_)" }
    },
    required: %w[person_id badge_id]
  )
  output_schema(
    type: "object",
    properties: { id: { type: "string" }, person: REF_SCHEMA, badge: REF_SCHEMA },
    required: %w[id person badge]
  )

  def call(person_id:, badge_id:)
    person = ctx.find(Person, person_id)
    badge = ctx.find(Badge, badge_id)
    assignment = badge.badge_assignments.build(person: person)
    ctx.authorize!(assignment, :create?)
    invalid_argument!(assignment.errors.full_messages.to_sentence) unless assignment.save

    changed!(assignment)
    { id: assignment.neat_id, person: person_json(person), badge: { id: badge.neat_id, name: badge.name } }
  end
end
