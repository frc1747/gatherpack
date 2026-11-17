# What the registration tools share: a registration as the registrations list and its
# page show it (index and show), and a sign-up as the page's "Waiting for email
# confirmation" table does: names and times, never an email.
module Mcp::IntakeRecords
  STATUSES = [ "open", "not open yet", "closed" ].freeze

  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      team: Mcp::Tool::REF_SCHEMA,
      status: { type: "string", enum: STATUSES },
      opens_at: { type: "string" },
      closes_at: { type: %w[string null] },
      self_service: { type: "boolean" },
      kiosk: { type: "boolean" }
    },
    required: %w[id title team status opens_at closes_at self_service kiosk]
  }.freeze

  ENTRY_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      teams: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      started_at: { type: "string" },
      network: { type: %w[string null], description: "The network the sign-up came from, as the page shows it" }
    },
    required: %w[id name teams started_at network]
  }.freeze

  private

  # The page's own words for where a registration is.
  def registration_status(registration)
    registration.open? ? "open" : (registration.not_yet_open? ? "not open yet" : "closed")
  end

  def registration_json(registration)
    {
      id: registration.neat_id,
      title: registration.title,
      team: team_json(registration.team),
      status: registration_status(registration),
      opens_at: time_json(registration.opens_at),
      closes_at: time_json(registration.closes_at),
      self_service: registration.self_service?,
      kiosk: registration.kiosk?
    }
  end

  # Same rules as create_event's times (CreateEvent::ISO8601_TIME): ISO 8601, in the app's
  # time zone without an offset, and no rolling a February 31 over.
  def parse_time(value, name)
    match = value.match(Mcp::Tools::CreateEvent::ISO8601_TIME)
    raise ArgumentError if match.nil? || (match[:offset] && Date._iso8601(value)[:offset].nil?)

    Date.iso8601(value.first(10))
    Time.zone.iso8601(value)
  rescue ArgumentError
    invalid_argument!("#{name} must be an ISO 8601 date-time like 2026-03-31T18:00:00")
  end

  def entry_json(entry)
    {
      id: entry.neat_id,
      name: "#{entry.first_name} #{entry.last_name}",
      teams: entry.teams.map { |team| team_json(team) },
      started_at: time_json(entry.created_at),
      network: entry.created_ip_prefix
    }
  end
end
