# Marks every active item sign-up at one event of a sheet brought, as the roster's Mark
# all brought does (RosterSignupsController#mark_all_brought, lines 116-129):
# SignupSheetPolicy#roster? (line 117), refused on an archived sheet (line 118), the event
# found among the sheet's (line 120), the same sign-ups (lines 121-122), and each one
# SignupPolicy#mark? refuses is left and listed with the page's reason (line 123).
#
# Against the page: it saves them in one transaction, so one failing would undo them all
# and show an error. Here each saves on its own and a failure is listed in skipped, as
# bulk_write does for every bulk tool. A sheet the viewer can't see is "Not found".
#
# Each row shows the status a real run gives it, so a dry_run row matches that run's.
#
# A repeat finds nothing left to mark, as on the page: only active sign-ups are taken.
class Mcp::Tools::MarkAllBrought < Mcp::Tool
  include Mcp::Tools::SignupRosterFormat

  tool_name "mark_all_brought"
  description "Mark every active item sign-up at one event of a sheet as brought, as the roster's Mark all brought does, leaving your own family's and listing them in skipped: " \
    "you get \"Not allowed\" on a sheet you don't organize, \"Not found\" for a sheet you can't see or an event not on it. With dry_run, lists what would change without changing it."
  scope :write
  feature :signups
  bulk
  input_schema(
    properties: {
      sheet_id: { type: "string", description: "The sheet's ID (sush_)" },
      event_id: { type: "string", description: "The event's ID (evt_), one of the sheet's" },
      dry_run: dry_run_property
    },
    required: %w[sheet_id event_id]
  )
  output_schema(bulk_output_schema(RESULT_SCHEMA))

  def call(sheet_id:, event_id:, dry_run: false)
    sheet = ctx.find(SignupSheet, sheet_id)
    ctx.authorize!(sheet, :roster?)
    invalid_argument!("This sheet is archived") if sheet.archived?

    event = ctx.find(sheet.events, event_id)
    signups = Signup.active.joins(signup_slot: :signup_position).includes(:person, :on_behalf_of, signup_slot: %i[ event signup_position ])
      .where(signup_slots: { event_id: event.id }, signup_positions: { signup_sheet_id: sheet.id, kind: :items })
      .order(:created_at, :id)

    bulk_write(signups, dry_run: dry_run,
      check: ->(signup) { ctx.allowed?(signup, :mark?) || raise(Mcp::NotAllowed, SignupSheet::SELF_APPROVAL_REASON) },
      json: ->(signup) { roster_result(signup).merge(status: "fulfilled") }) { |signup| signup.update(status: :fulfilled) }
  end
end
