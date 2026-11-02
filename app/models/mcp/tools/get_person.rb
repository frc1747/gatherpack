# One person's profile, as PeopleController#show and people/show render it:
# the person must be in policy_scope(Person) and PersonPolicy#show? must allow
# it (either failing is "Not found"/"Not allowed" as the page does). The page
# shows everyone who passes that check the same fields, so contact details
# (email, phone, address, birthday, dietary restrictions, shirt size, gender)
# are returned to all of them; nothing is hidden by relationship. Teams are
# the person's teams and their ancestors that are in policy_scope(Team), with
# the manager flag from the person's own memberships. Badges are the person's
# badges in policy_scope(Badge), and only while the badges feature is on.
# Relationships are policy_scope(person.relationships), each with the other
# person (named even when the viewer can't open their profile, as the page
# does) and the label the page shows for them. Admin and architect flags, tokens,
# ledgers and time clock hours are not returned.
#
# Mcp.person_extensions add keys (person fields, for one); see Mcp.
class Mcp::Tools::GetPerson < Mcp::Tool
  tool_name "get_person"
  description "A person's profile as you can see it: name, contact details, bio, the teams they belong to " \
    "(with whether they manage each), their badges and their relationships to other people."
  scope :read
  input_schema(properties: { person_id: { type: "string", description: "Person ID (per_...)" } }, required: [ "person_id" ])
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      first_name: { type: %w[string null] },
      last_name: { type: %w[string null] },
      bio: { type: %w[string null] },
      email: { type: %w[string null] },
      phone_number: { type: %w[string null] },
      birthday: { type: %w[string null] },
      address: { type: %w[string null] },
      dietary_restrictions: { type: %w[string null] },
      shirt_size: { type: %w[string null] },
      gender: { type: %w[string null] },
      teams: { type: "array", items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" }, manager: { type: "boolean" } }, required: %w[id name manager] } },
      badges: { type: "array", items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" } }, required: %w[id name] } },
      relationships: { type: "array", items: { type: "object", properties: { label: { type: "string" }, person: REF_SCHEMA }, required: %w[label person] } }
    },
    required: %w[id name teams relationships]
  )

  def call(person_id:)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :show?)

    result = {
      id: person.neat_id,
      name: person.display_name,
      first_name: person.first_name,
      last_name: person.last_name,
      bio: person.bio,
      email: person.user&.email,
      phone_number: person.phone_number,
      birthday: date_json(person.birthday),
      address: person.address,
      dietary_restrictions: person.dietary_restrictions,
      shirt_size: person.shirt_size,
      gender: person.gender,
      teams: teams_json(person),
      relationships: relationships_json(person)
    }
    result[:badges] = badges_json(person) if GatherPack::Features.enabled?(:badges)
    extensions_json(person).merge(result)
  end

  private

  def teams_json(person)
    managed = person.memberships.where(manager: true).pluck(:team_id)
    ctx.policy_scope(person.all_ancestor_teams).order(:name, :id).map do |team|
      team_json(team).merge(manager: managed.include?(team.id))
    end
  end

  def badges_json(person)
    ctx.policy_scope(person.badges).order(:name, :id).map { |badge| { id: badge.neat_id, name: badge.name } }
  end

  def relationships_json(person)
    ctx.policy_scope(person.relationships).includes(:relationship_type, :parent, :child).order(:created_at, :id).map do |relationship|
      host_is_parent = relationship.parent_id == person.id
      {
        label: host_is_parent ? relationship.relationship_type.child_label : relationship.relationship_type.parent_label,
        person: person_json(host_is_parent ? relationship.child : relationship.parent)
      }
    end
  end

  # An extension that raises, or returns something other than a Hash, adds
  # nothing: the profile is still returned.
  def extensions_json(person)
    Mcp.person_extensions.each_with_object({}) do |extension, merged|
      extra = extension.call(person, ctx.person)
      raise TypeError, "returned #{extra.class}, not a Hash" unless extra.is_a?(Hash)

      merged.merge!(extra.symbolize_keys)
    rescue => e
      Rails.logger.error("[MCP] get_person extension failed (request #{ctx.request_id}): #{e.class}: #{e.message}")
    end
  end
end
