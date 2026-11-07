# Kiosk sign-ups whose person hasn't opened their invitation, as
# Intake::RegistrationsController#waiting and its view show them (lines 79-83): entries from
# the kiosk, unverified, with a person, oldest first, with what managers need to chase them.
# Found and authorized waiting? (the team's managers and admins), so one you can't run is
# "Not found". The page's Send again is rate limited and sends mail, so it isn't offered, and
# a guardian's email, which the page puts in a field to correct, is left out: no emails.
# The person's own page link and name are the same ones people_ tools give.
class Mcp::Tools::ListWaitingToFinish < Mcp::Tool
  GUARDIAN_STATES = [ "confirmed", "waiting for a manager to confirm", "waiting for the guardian to confirm" ].freeze

  ITEM_SCHEMA = {
    type: "object",
    properties: {
      entry_id: { type: "string" },
      person: Mcp::Tool::REF_SCHEMA,
      teams: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      invited_at: { type: "string" },
      days_ago: { type: "integer" },
      email_not_opened: { type: "boolean", description: "True from the third day, when the page shows its warning" },
      no_guardian_yet: { type: "boolean" },
      possible_match: { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ], description: "Someone on file they might be; link or keep separate on the page" },
      guardian_requests: {
        type: "array",
        items: {
          type: "object",
          properties: { name: { type: "string" }, status: { type: "string", enum: GUARDIAN_STATES } },
          required: %w[name status]
        }
      }
    },
    required: %w[entry_id person teams invited_at days_ago email_not_opened no_guardian_yet possible_match guardian_requests]
  }.freeze

  tool_name "list_waiting_to_finish"
  description "Kiosk sign-ups still waiting to open their invitation, oldest first, with how long, whether a guardian is missing and any possible match. No email addresses."
  scope :read
  feature :intake
  input_schema(
    properties: {
      registration_id: { type: "string", description: "The registration's ID (ireg_)" },
      limit: limit_property
    },
    required: %w[registration_id]
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: ITEM_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(registration_id:, limit: DEFAULT_LIMIT)
    registration = ctx.find(Intake::Registration, registration_id)
    ctx.authorize!(registration, :waiting?)

    entries = registration.entries.source_kiosk.unverified.where.not(person_id: nil)
      .includes(:person, :household_members).order(:created_at, :id)
    list(entries, limit: limit) { |entry| item_json(entry) }
  end

  private

  def item_json(entry)
    days = ((Time.current - entry.created_at) / 1.day).floor
    member = entry.household_members.detect(&:applicant?)
    guardians = entry.household_members.select(&:guardian?)
    match = member&.possible_match
    {
      entry_id: entry.neat_id,
      person: person_json(entry.person),
      teams: entry.teams.map { |team| team_json(team) },
      invited_at: time_json(entry.created_at),
      days_ago: days,
      email_not_opened: days >= 3,
      no_guardian_yet: entry.facts["needs_guardian"] && guardians.none? && !entry.person.guardians.exists? ? true : false,
      possible_match: match && person_json(match),
      guardian_requests: guardians.map { |row| guardian_json(row) }
    }
  end

  # The wording of the page's guardian badges, minus the email.
  def guardian_json(row)
    name = row.person&.display_name.presence || [ row.facts["first_name"], row.facts["last_name"] ].compact_blank.join(" ")
    status = if row.guardian_confirmed_at then "confirmed"
    elsif row.facts["manager_confirms"] then "waiting for a manager to confirm"
    else "waiting for the guardian to confirm"
    end
    { name: name, status: status }
  end
end
