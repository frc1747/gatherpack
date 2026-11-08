# A registration's sign-ups, as Intake::RegistrationsController#show shows them (lines 17-21,
# the view's two tables): counts by day in the site's time zone for the last 30 days, and the people still to
# confirm their email (unverified, no person yet), newest first, with the network prefix
# the page shows. Found and authorized as get_registration is. No email, ever: the page
# shows none, and the entry holds the address encrypted. Kiosk sign-ups, who have a person
# at once, are list_waiting_to_finish.
class Mcp::Tools::ListIntakeEntries < Mcp::Tool
  include Mcp::IntakeRecords

  DAY_SCHEMA = {
    type: "object",
    properties: { day: { type: "string" }, started: { type: "integer" }, email_confirmed: { type: "integer" } },
    required: %w[day started email_confirmed]
  }.freeze

  tool_name "list_intake_entries"
  description "A registration's sign-ups: counts by day for the last 30 days, and who is waiting to confirm their email, newest first. No email addresses."
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
    properties: {
      by_day: { type: "array", items: DAY_SCHEMA },
      items: { type: "array", items: Mcp::IntakeRecords::ENTRY_SCHEMA },
      truncated: { type: "boolean" }
    },
    required: %w[by_day items truncated]
  )

  def call(registration_id:, limit: DEFAULT_LIMIT)
    registration = ctx.find(Intake::Registration, registration_id)
    ctx.authorize!(registration, :show?)

    entries = registration.entries
    started = entries.counts_by_day
    confirmed = entries.verified.counts_by_day
    waiting = registration.unverified_entries.where(person_id: nil).order(created_at: :desc, id: :asc)

    {
      by_day: started.sort_by { |day, _| day }.reverse.map { |day, count| { day: day.to_date.iso8601, started: count, email_confirmed: confirmed[day] || 0 } },
      **list(waiting, limit: limit) { |entry| entry_json(entry) }
    }
  end
end
