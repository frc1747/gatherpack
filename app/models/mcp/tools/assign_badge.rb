# Gives a person a badge, as BadgeAssignmentsController#create does.
#
# Mirrors: set_badge (line 55, the badge in policy_scope(Badge)), create (lines
# 28-30: build through the badge, authorize create?, save). BadgeAssignmentPolicy#create?
# is BadgePolicy#update?, so the badge's permission decides who may grant it, the
# viewer's own grant included: a member can't give themselves an "added by admin"
# or "added by manager" badge. The model's team badge membership and duplicate
# validations come back as invalid-argument errors.
#
# Narrower than the POST, which doesn't check the person at all, in two ways. The
# person must be in policy_scope(Person), since this result names them. And
# BadgePolicy#update? passes everyone on a self-service badge ("...or self", "has
# account"), so there a non-admin may only choose themselves or people they manage.
# Against the form, whose combobox is the team's people for a team badge and managed
# people otherwise: this adds self-grant, and on a self-service team badge leaves out
# teammates the viewer doesn't manage.
class Mcp::Tools::AssignBadge < Mcp::Tool
  SELF_SERVICE_PERMISSIONS = %w[added_by_admin_or_self added_by_manager_or_self has_account].freeze

  tool_name "assign_badge"
  description "Give a person a badge. Team badges need the person on the badge's team. " \
    "On a badge open to self-service, you can choose only yourself or people you manage, unless you're an admin. Returns the new assignment."
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
    raise Mcp::NotAllowed if SELF_SERVICE_PERMISSIONS.include?(badge.permission) && person != ctx.person && !ctx.person.can_manage(person)

    invalid_argument!(assignment.errors.full_messages.to_sentence) unless assignment.save

    changed!(assignment)
    { id: assignment.neat_id, person: person_json(person), badge: { id: badge.neat_id, name: badge.name } }
  end
end
