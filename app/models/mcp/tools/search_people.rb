# People whose name contains the query, as the people index finds them
# (PeopleController#index: policy_scope(Person), display_name_i_cont).
# The team filter takes a team in policy_scope(Team) and matches its direct
# members. The badge filter needs the badges feature and a badge in
# policy_scope(Badge), and matches its holders; results stay within
# policy_scope(Person) either way, so neither filter reveals anyone the
# people index wouldn't. Each person's teams are their direct teams that are
# in policy_scope(Team).
class Mcp::Tools::SearchPeople < Mcp::Tool
  tool_name "search_people"
  description "Find people by name (case-insensitive, matches part of the name). Returns at most `limit` people " \
    "you can see, with their teams, ordered by last name. Optionally only members of a team or holders of a badge."
  scope :read
  input_schema(
    properties: {
      query: { type: "string", minLength: 1, description: "Part of the person's name" },
      team_id: { type: "string", description: "Only direct members of this team (tm_ ID)" },
      badge_id: { type: "string", description: "Only holders of this badge (bdg_ ID)" },
      limit: limit_property
    },
    required: [ "query" ]
  )
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
            teams: { type: "array", items: REF_SCHEMA }
          },
          required: %w[id name teams]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(query:, team_id: nil, badge_id: nil, limit: DEFAULT_LIMIT)
    invalid_argument!("query can't be blank") if query.strip.empty?

    people = ctx.policy_scope(Person).ransack(display_name_i_cont: query.strip).result(distinct: true)
    people = people.where(id: Membership.where(team: ctx.find(ctx.policy_scope(Team), team_id)).select(:person_id)) if team_id
    people = people.where(id: BadgeAssignment.where(badge: visible_badge(badge_id)).select(:person_id)) if badge_id

    result = list(people.order(:last_name, :first_name, :id), limit: limit) { |person| person }
    teams_by_person = Membership.where(person_id: result[:items].map(&:id), team_id: ctx.policy_scope(Team).select(:id))
      .includes(:team).group_by(&:person_id)

    result.merge(items: result[:items].map do |person|
      teams = (teams_by_person[person.id] || []).map(&:team).uniq.sort_by { |team| [ team.name.to_s, team.id ] }
      person_json(person).merge(teams: teams.map { |team| team_json(team) })
    end)
  end

  private

  def visible_badge(badge_id)
    raise Mcp::FeatureOff, "Badges are off" unless GatherPack::Features.enabled?(:badges)

    ctx.find(ctx.policy_scope(Badge), badge_id)
  end
end
