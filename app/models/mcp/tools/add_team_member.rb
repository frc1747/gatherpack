# Adds a person to a team, as MembershipsController#create does on the team route.
#
# Mirrors: set_team_or_person (line 99, the team in policy_scope(Team)), create (lines
# 45-47: build, authorize create?, save). MembershipPolicy#create? is the whole rule,
# whatever the team's join permission: admins and the team's managers (ancestors' too)
# may add anyone, and set manager. Anyone else may only add themselves to a team that
# is open to any account ("has_account"), never as a manager; on any other join
# permission, requires_approval included, they're refused. The flag is passed to the
# policy, so manager: true from someone who can't set it refuses the call rather than
# being dropped. The model's duplicate validation comes back as an invalid-argument error.
#
# Narrower than the team route's POST, which doesn't check the person at all: the
# person must be in policy_scope(Person), since this result names them, and a
# non-admin may only add themselves or people they manage (all_managed_people). That
# matches the form, which offers managed people, and adds only the viewer themselves.
class Mcp::Tools::AddTeamMember < Mcp::Tool
  tool_name "add_team_member"
  description "Add a person to a team, optionally as a manager. Team managers can add people they manage or themselves, admins anyone; " \
    "anyone else can only add themselves to a team open to any account. Returns the new membership."
  scope :write
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      team_id: { type: "string", description: "The team's ID (tm_)" },
      manager: { type: "boolean", description: "Make them a manager of the team (default false)" }
    },
    required: %w[person_id team_id]
  )
  output_schema(
    type: "object",
    properties: { id: { type: "string" }, person: REF_SCHEMA, team: REF_SCHEMA, manager: { type: "boolean" } },
    required: %w[id person team manager]
  )

  def call(person_id:, team_id:, manager: false)
    person = ctx.find(Person, person_id)
    team = ctx.find(Team, team_id)
    membership = team.memberships.build(person: person, manager: manager)
    ctx.authorize!(membership, :create?)
    raise Mcp::NotAllowed unless person == ctx.person || ctx.person.can_manage(person)

    invalid_argument!(membership.errors.full_messages.to_sentence) unless membership.save

    changed!(membership)
    { id: membership.neat_id, person: person_json(person), team: team_json(team), manager: membership.manager? }
  end
end
