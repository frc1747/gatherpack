# Progress on one commitment, as the commitment page and the person's
# commitments tab show it. The commitment must pass CommitmentPolicy#show?, as
# CommitmentsController#set_commitment requires, otherwise "Not found". (Not
# policy_scope(Commitment), which checks every commitment to find one.)
#
# Without person_id, an organizer (CommitmentPolicy#progress?) gets the
# progress table: a row per person, or per group when the commitment is
# grouped, with owed, confirmed, planned and remaining and the per-source
# breakdown, in name order, at most `limit`; filter narrows the rows as the
# page's filter does (met, not_met, nothing_planned) before the limit applies.
# Filter only applies to that table. Anyone else gets their own row
# (Commitment#progress_seen_by: their group's, or that of the group they're
# related to), with the credits behind it.
#
# With person_id, one person's row with the credits and what each came from
# (the tab's _progress card). The person must owe the commitment, and the
# viewer must run it, be that person (a relative who doesn't owe gets the group
# they're related to, as their own commitments tab shows), or be related
# through the group relationship type to someone in that person's group
# (Commitment#group_relative_of?, the PersonCommitmentsPolicy rule);
# otherwise "Not found", the same as an unknown person. Person lookup is by ID
# alone, as PersonCommitmentsController does, since the commitment decides.
# A source's confirmed credit is its records after the ratio and cap
# (per, credits, max_credits, partial, capped), so records may outnumber it.
# Needs the commitments feature.
class Mcp::Tools::CommitmentProgress < Mcp::Tool
  AMOUNT = { type: "integer" }.freeze
  FILTERS = %w[ met not_met nothing_planned ].freeze

  tool_name "commitment_progress"
  description "Progress on a commitment you can see: owed, confirmed, planned and remaining per person or group. " \
    "Organizers get every row (filter: met, not_met or nothing_planned); others get their own. " \
    "With person_id, one person's row with each record and what it came from; a record may count for less than a credit (see sources)."
  scope :read
  feature :commitments
  input_schema(
    properties: {
      commitment_id: { type: "string", description: "The commitment's ID (cmt_)" },
      person_id: { type: "string", description: "Only this person's row, with the records (per_). Optional." },
      filter: { type: "string", enum: FILTERS, description: "Organizers' table only: show just met, not_met or nothing_planned rows. Optional." },
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
                properties: {
                  source: { type: "string" }, available: { type: "boolean" }, confirmed: AMOUNT, planned: AMOUNT,
                  per: AMOUNT, credits_per: AMOUNT, max_credits: { type: %w[integer null] }, partial: AMOUNT, capped: { type: "boolean" }
                },
                required: %w[source available confirmed planned per credits_per max_credits partial capped]
              }
            },
            adjustments: {
              type: "array",
              items: { type: "object", properties: { person: REF_SCHEMA, credits: AMOUNT, reason: { type: "string" } }, required: %w[person credits reason] }
            },
            records: {
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

  def call(commitment_id:, person_id: nil, filter: nil, limit: DEFAULT_LIMIT)
    commitment = ctx.find(Commitment.all, commitment_id)
    not_found! unless ctx.allowed?(commitment, :show?)
    organizer = ctx.allowed?(commitment, :progress?)
    rows =
      if person_id
        [ detailed(person_progress(commitment, person_id, organizer)) ]
      elsif organizer
        commitment.progress(commitment.owing_people.order(:last_name, :first_name, :id)).values.uniq.select { |progress| matches?(progress, filter) }.map { |progress| summary(progress) }
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
    return commitment.progress_seen_by(person) || not_found! if person.id == ctx.person.id

    allowed = organizer || commitment.group_relative_of?(ctx.person, person)
    not_found! unless allowed && commitment.covers?(person)

    commitment.progress_for(person)
  end

  def matches?(progress, filter)
    case filter
    when "met" then progress.met?
    when "not_met" then !progress.met?
    when "nothing_planned" then progress.nothing_planned?
    else true
    end
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
        { source: line.source.label, available: line.available?, confirmed: line.confirmed_credits, planned: line.planned_credits,
          per: line.source.per, credits_per: line.source.credits, max_credits: line.source.max_credits, partial: line.partial, capped: line.capped ? true : false }
      end,
      adjustments: progress.adjustments.map { |adjustment| adjustment_json(progress, adjustment) }
    }
  end

  # The summary plus each record behind the credits, as the _progress card
  # lists them.
  def detailed(progress)
    people = (progress.members + progress.relatives).index_by(&:id)
    records = progress.lines.flat_map do |line|
      line.records.map do |record|
        { source: line.source.label, date: date_json(record.date), label: record.label.to_s, confirmed: record.confirmed?,
          person: person_json(people.fetch(record.person_id)) }
      end
    end
    summary(progress).merge(records: records.sort_by { |record| [ record[:date], record[:source], record[:label] ] })
  end

  def adjustment_json(progress, adjustment)
    member = progress.members.find { |candidate| candidate.id == adjustment.person_id }
    { person: person_json(member), credits: adjustment.credits, reason: adjustment.reason }
  end
end
