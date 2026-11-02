# Progress on one commitment, as the commitment page and the person's
# commitments tab show it. The commitment must be in policy_scope(Commitment)
# (CommitmentsController#set_commitment authorizes show?), otherwise "Not found".
#
# Without person_id, an organizer (CommitmentPolicy#progress?) gets the
# progress table: a row per person, or per group when the commitment is
# grouped, with owed, confirmed, planned and remaining and the per-source
# breakdown, in name order, at most `limit`. Anyone else gets their own row
# (Commitment#progress_seen_by: their group's, or that of the group they're
# related to), with the credits behind it.
#
# With person_id, one person's row with the credits and what each came from
# (the tab's _progress card). The person must owe the commitment, and the
# viewer must run it, be that person, or be related through the group
# relationship type to someone in that person's group
# (Commitment#group_relative_of?, the PersonCommitmentsPolicy rule);
# otherwise "Not found", the same as an unknown person. Person lookup is by ID
# alone, as PersonCommitmentsController does, since the commitment decides.
# Needs the commitments feature.
class Mcp::Tools::CommitmentProgress < Mcp::Tool
  AMOUNT = { type: "integer" }.freeze

  tool_name "commitment_progress"
  description "Progress on a commitment you can see: owed, confirmed, planned and remaining per person or group. " \
    "Organizers get every row; others get their own. With person_id, one person's row with each credit and what it came from."
  scope :read
  feature :commitments
  input_schema(
    properties: {
      commitment_id: { type: "string", description: "The commitment's ID (cmt_)" },
      person_id: { type: "string", description: "Only this person's row, with the credits (per_). Optional." },
      limit: limit_property
    },
    required: [ "commitment_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      commitment: {
        type: "object",
        properties: { id: { type: "string" }, title: { type: "string" }, unit: { type: "string" }, counts_when: { type: "string" },
                      starts_on: { type: "string" }, ends_on: { type: "string" } },
        required: %w[id title unit counts_when starts_on ends_on]
      },
      rows: {
        type: "array",
        items: {
          type: "object",
          properties: {
            people: { type: "array", items: REF_SCHEMA },
            owed: AMOUNT,
            confirmed: AMOUNT,
            planned: AMOUNT,
            remaining: AMOUNT,
            met: { type: "boolean" },
            sources: {
              type: "array",
              items: {
                type: "object",
                properties: { source: { type: "string" }, available: { type: "boolean" }, confirmed: AMOUNT, planned: AMOUNT },
                required: %w[source available confirmed planned]
              }
            },
            adjustments: {
              type: "array",
              items: { type: "object", properties: { person: REF_SCHEMA, credits: AMOUNT, reason: { type: "string" } }, required: %w[person credits reason] }
            },
            credits: {
              type: "array",
              items: {
                type: "object",
                properties: { source: { type: "string" }, date: { type: "string" }, label: { type: "string" }, confirmed: { type: "boolean" }, person: REF_SCHEMA },
                required: %w[source date label confirmed person]
              }
            }
          },
          required: %w[people owed confirmed planned remaining met sources adjustments]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[commitment rows truncated]
  )

  def call(commitment_id:, person_id: nil, limit: DEFAULT_LIMIT)
    commitment = ctx.find(Commitment, commitment_id)
    organizer = ctx.allowed?(commitment, :progress?)
    rows =
      if person_id
        [ detailed(person_progress(commitment, person_id, organizer)) ]
      elsif organizer
        commitment.progress(commitment.owing_people.order(:last_name, :first_name, :id)).values.uniq.map { |progress| summary(progress) }
      else
        [ detailed(commitment.progress_seen_by(ctx.person) || not_found!) ]
      end

    limit = limit.to_i.clamp(1, MAX_LIMIT)
    {
      commitment: {
        id: commitment.neat_id, title: commitment.title, unit: commitment.unit, counts_when: commitment.counts_when,
        starts_on: date_json(commitment.starts_on), ends_on: date_json(commitment.ends_on)
      },
      rows: rows.first(limit),
      truncated: rows.size > limit
    }
  end

  private

  def person_progress(commitment, person_id, organizer)
    person = Mcp.find_by_neat_id(Person, person_id) || not_found!
    allowed = organizer || person.id == ctx.person.id || commitment.group_relative_of?(ctx.person, person)
    not_found! unless allowed && commitment.covers?(person)

    commitment.progress_for(person)
  end

  def summary(progress)
    {
      people: progress.members.map { |member| person_json(member) },
      owed: progress.owed,
      confirmed: progress.confirmed,
      planned: progress.planned,
      remaining: progress.remaining,
      met: progress.met?,
      sources: progress.lines.map do |line|
        { source: line.source.label, available: line.available?, confirmed: line.confirmed_credits, planned: line.planned_credits }
      end,
      adjustments: progress.adjustments.map { |adjustment| adjustment_json(progress, adjustment) }
    }
  end

  # The summary plus each record behind the credits, as the _progress card
  # lists them.
  def detailed(progress)
    people = (progress.members + progress.relatives).index_by(&:id)
    credits = progress.lines.flat_map do |line|
      line.records.map do |record|
        { source: line.source.label, date: date_json(record.date), label: record.label.to_s, confirmed: record.confirmed?,
          person: person_json(people.fetch(record.person_id)) }
      end
    end
    summary(progress).merge(credits: credits.sort_by { |credit| [ credit[:date], credit[:source], credit[:label] ] })
  end

  def adjustment_json(progress, adjustment)
    member = progress.members.find { |candidate| candidate.id == adjustment.person_id }
    { person: person_json(member), credits: adjustment.credits, reason: adjustment.reason }
  end
end
