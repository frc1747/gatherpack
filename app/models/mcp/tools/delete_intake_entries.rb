# Deletes sign-ups that haven't confirmed their email, as Intake::RegistrationsController
# #destroy_entries does (lines 75-78, "Delete selected"): the registration is found through
# policy_scope and authorized destroy_entries? (the team's managers and admins), then of the
# ticked entries only those unverified with no person yet are destroyed. The page ignores
# the rest without a word; this lists them as skipped, with why. Entries of another
# registration are "Not found", as they are on the page. Never a person or a login:
# deleting people is the admin-only spam screen, which isn't offered.
class Mcp::Tools::DeleteIntakeEntries < Mcp::Tool
  include Mcp::IntakeRecords

  tool_name "delete_intake_entries"
  description "Delete sign-ups that haven't confirmed their email, as Delete selected does on a registration's page. " \
    "Confirmed sign-ups and kiosk sign-ups with a person are skipped. Use dry_run first to see what would go."
  scope :write
  destructive
  feature :intake
  bulk
  input_schema(
    properties: {
      registration_id: { type: "string", description: "The registration's ID (ireg_)" },
      entry_ids: { type: "array", items: { type: "string" }, minItems: 1, maxItems: BULK_LIMIT, description: "The sign-ups' IDs (ient_), from list_intake_entries" },
      dry_run: dry_run_property
    },
    required: %w[registration_id entry_ids],
    closed: true
  )
  output_schema(bulk_output_schema(Mcp::IntakeRecords::ENTRY_SCHEMA))

  def call(registration_id:, entry_ids:, dry_run: false)
    registration = ctx.find(Intake::Registration, registration_id)
    ctx.authorize!(registration, :destroy_entries?)

    entries = entry_ids.uniq.map { |id| Mcp.find_by_neat_id(registration.entries, id) || not_found! }
    bulk_write(entries, dry_run: dry_run, json: ->(entry) { entry_json(entry) },
      check: ->(entry) { unconfirmed?(entry) }) { |entry| entry.destroy }
  end

  private

  def unconfirmed?(entry)
    raise Mcp::InvalidArgument, "Already confirmed" if entry.verified_at
    raise Mcp::InvalidArgument, "Has a person (kiosk sign-up)" if entry.person_id

    true
  end
end
