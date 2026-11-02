# One person's profile, as PeopleController#show and people/show render it:
# the person must be in policy_scope(Person) and PersonPolicy#show? must allow
# it (either failing is "Not found"/"Not allowed" as the page does). Contact
# details (PROFILE_FIELD_KEYS) are returned to all of them unless an
# Mcp.person_filters entry leaves a key out, and an omitted key is not the same
# as null, which means empty. If a filter fails, or the build has field-level
# read rules and no filter, all of those keys are omitted and the rest of the
# profile is still returned. Teams are the person's teams and their ancestors
# that are in policy_scope(Team), with the manager flag from the person's own
# memberships. Badges are the person's badges in policy_scope(Badge), and only
# while the badges feature is on. membership_id and badge_assignment_id are what
# remove_team_member and remove_badge take; each is null unless the viewer may
# remove that record (the tool's own check: destroy?, and for a badge assignment
# RemoveBadge.removable?), and membership_id is also null for a team the person
# only inherits.
# Relationships are policy_scope(person.relationships), each with the other
# person (named even when the viewer can't open their profile, as the page
# does) and the label the page shows for them. Admin and architect flags, tokens,
# ledgers and time clock hours are not returned.
#
# Mcp.person_extensions add keys (person fields, for one); see Mcp.
class Mcp::Tools::GetPerson < Mcp::Tool
  # The keys Mcp.person_filters decide on. The bio isn't one: people/show renders
  # it outside its list of fields, whatever that list's read rules are.
  PROFILE_FIELD_KEYS = %w[email phone_number birthday address dietary_restrictions shirt_size gender].freeze

  tool_name "get_person"
  description "A person's profile as you can see it: name, contact details, bio, the teams they belong to " \
    "(with whether they manage each), their badges and their relationships to other people. " \
    "Membership and badge assignment IDs are given only where you may remove them. " \
    "Fields you can't see are left out; null means the field is empty."
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
      teams: { type: "array", items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" }, manager: { type: "boolean" }, membership_id: { type: %w[string null] } }, required: %w[id name manager membership_id] } },
      badges: { type: "array", items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" }, badge_assignment_id: { type: %w[string null] } }, required: %w[id name badge_assignment_id] } },
      relationships: { type: "array", items: { type: "object", properties: { label: { type: "string" }, person: REF_SCHEMA }, required: %w[label person] } }
    },
    required: %w[id name teams relationships]
  )

  def call(person_id:)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :show?)

    result = {
      id: person.neat_id,
      name: person_json(person)[:name],
      first_name: person.first_name,
      last_name: person.last_name,
      bio: person.bio,
      email: person.user&.email.presence,
      phone_number: person.phone_number.presence,
      birthday: date_json(person.birthday),
      address: person.address.presence,
      dietary_restrictions: person.dietary_restrictions.presence,
      shirt_size: person.shirt_size.presence,
      gender: person.gender.presence,
      teams: teams_json(person),
      relationships: relationships_json(person)
    }
    result[:badges] = badges_json(person) if GatherPack::Features.enabled?(:badges)
    hidden = PROFILE_FIELD_KEYS - kept_profile_keys(person)
    # After the merge, so an extension can't put back a key that was left out.
    extensions_json(person).merge(result).except(*hidden.map(&:to_sym))
  end

  private

  def kept_profile_keys(person)
    return [] if field_rules_without_filter?

    Mcp.person_filters.reduce(PROFILE_FIELD_KEYS) { |kept, filter| kept & keys_kept_by(filter, person) }
  end

  # A build whose Person has field-level read rules needs a filter to apply them
  # here. Without one, the contact details are left out rather than shown to
  # viewers those rules may exclude.
  def field_rules_without_filter?
    Mcp.person_filters.empty? && Person.method_defined?(:readable_fields_for)
  end

  # Runs in a savepoint, as extensions_json does. The "|| raise" covers a filter
  # raising ActiveRecord::Rollback, which the transaction swallows.
  def keys_kept_by(filter, person)
    ActiveRecord::Base.transaction(requires_new: true) do
      keys = filter.call(person, ctx.person)
      raise TypeError, "returned #{keys.class}, not an Array" unless keys.is_a?(Array)

      keys.map(&:to_s)
    end || raise("rolled back")
  rescue StandardError, ScriptError => e
    Rails.logger.error("[MCP] get_person filter failed (request #{ctx.request_id}): #{e.class}: #{e.message}")
    []
  end

  def teams_json(person)
    memberships = person.memberships.index_by(&:team_id)
    ctx.policy_scope(person.all_ancestor_teams).order(:name, :id).map do |team|
      membership = memberships[team.id]
      team_json(team).merge(manager: membership&.manager == true, membership_id: membership && ctx.allowed?(membership, :destroy?) ? membership.neat_id : nil)
    end
  end

  def badges_json(person)
    assignments = person.badge_assignments.index_by(&:badge_id)
    ctx.policy_scope(person.badges).order(:name, :id).map do |badge|
      assignment = assignments.fetch(badge.id)
      { id: badge.neat_id, name: badge.name, badge_assignment_id: Mcp::Tools::RemoveBadge.removable?(ctx, assignment) ? assignment.neat_id : nil }
    end
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

  # An extension that raises (even a ScriptError), returns something other than
  # a Hash, or returns a value that can't be turned into JSON (such as invalid UTF-8) adds nothing: the
  # profile is still returned. Each runs in a savepoint, so a failed query
  # inside one doesn't abort the request's transaction.
  def extensions_json(person)
    Mcp.person_extensions.each_with_object({}) do |extension, merged|
      extra = ActiveRecord::Base.transaction(requires_new: true) do
        value = extension.call(person, ctx.person)
        raise TypeError, "returned #{value.class}, not a Hash" unless value.is_a?(Hash)

        value.as_json.symbolize_keys.tap { |json| JSON.generate(json) }
      end
      merged.merge!(extra)
    rescue StandardError, ScriptError => e
      Rails.logger.error("[MCP] get_person extension failed (request #{ctx.request_id}): #{e.class}: #{e.message}")
    end
  end
end
