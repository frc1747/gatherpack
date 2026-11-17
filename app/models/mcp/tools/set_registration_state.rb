# Opens or closes a registration, which is setting its dates: there is no state column
# (Intake::Registration, "open means now is between opens_at and closes_at").
#
# Close is the page's Close now (Intake::RegistrationsController#close, line 62): closes_at
# becomes now unless it is closed already; policy close? (the team's managers and admins).
# Open is what the edit page does with the dates, so update? (the same rule): a registration
# not open yet opens now, and a closed one loses its end date, or takes closes_at when one
# is given. One already open is left as it is, except that closes_at is set when given.
# The registration's own validation applies (an end after the start), as it does on the
# page's save, and comes back as an invalid-argument error. The "opened" and "closed" hooks
# fire from Intake::RegistrationDatesJob, as for the page.
class Mcp::Tools::SetRegistrationState < Mcp::Tool
  include Mcp::IntakeRecords

  tool_name "set_registration_state"
  description "Open or close a registration by setting its dates. close: ends it now, as Close now does. " \
    "open: opens it now if it hasn't opened, and takes away the end date of a closed one (or sets closes_at, when given). Returns the registration."
  scope :write
  feature :intake
  input_schema(
    properties: {
      registration_id: { type: "string", description: "The registration's ID (ireg_)" },
      state: { type: "string", enum: %w[open close], description: "open or close" },
      closes_at: { type: "string", description: "With open: when it should close, ISO 8601 date-time. Default none." }
    },
    required: %w[registration_id state]
  )
  output_schema(Mcp::IntakeRecords::SCHEMA)

  def call(registration_id:, state:, closes_at: nil)
    registration = ctx.find(Intake::Registration, registration_id)
    if state == "close"
      invalid_argument!("closes_at is for open") if closes_at
      ctx.authorize!(registration, :close?)
      registration.update!(closes_at: Time.current) unless registration.closed?
    else
      ctx.authorize!(registration, :update?)
      reopen(registration, closes_at)
    end

    changed!(registration)
    registration_json(registration)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  def reopen(registration, closes_at)
    end_time = closes_at && parse_time(closes_at, "closes_at")
    changes = {}
    changes[:opens_at] = Time.current if registration.not_yet_open?
    changes[:closes_at] = end_time if end_time
    changes[:closes_at] = nil if registration.closed? && end_time.nil?
    registration.update!(changes) if changes.any?
  end
end
