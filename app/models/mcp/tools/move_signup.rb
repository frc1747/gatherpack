# Moves a sign-up to another slot on its sheet, as the roster's Move does
# (RosterSignupsController#move, lines 98-110): SignupPolicy#move? (set_signup, line
# 138), the slot found among the sheet's (line 99), SignupPolicy#override? when
# override_rules is set (line 101), Signup#change! for the row locks, capacity, rules
# and question, then SignupNotices#moved if the slot differs (line 105). One call, not
# a remove and a place. Signup#change! also reschedules the reminder and runs the hooks.
# The sheet must pass SignupSheetPolicy#show? or the sign-up is "Not found": the roster
# has no such step, but refuses all the same at move?.
#
# Moving to the slot it's already in does what the page does: it saves nothing new and
# sends no notices, though signups - update hooks run again, and the page still says
# "moved". Here the result says changed: false and the call log records no change, so a
# repeated call is safe to retry.
class Mcp::Tools::MoveSignup < Mcp::Tool
  include Mcp::Tools::SignupRosterFormat

  tool_name "move_signup"
  description "Move a sign-up to another slot on the same sheet, as the roster's Move does, emailing the people on it: capacity and the position's rules " \
    "apply unless override_rules is set, and you get \"Not allowed\" on a sheet you don't organize or for your own family's sign-up, \"Not found\" for a sheet you can't see. " \
    "Moving it to the slot it's already in saves nothing new and sends no notices, though signups - update hooks run again, as on the page, and returns changed: false."
  scope :write
  feature :signups
  input_schema(
    properties: {
      signup_id: { type: "string", description: "The sign-up's ID (sup_)" },
      slot_id: { type: "string", description: "The slot to move it to (susl_), from get_signup_sheet" },
      override_rules: { type: "boolean", description: "Move even though they don't meet the new position's rules (default false)" }
    },
    required: %w[signup_id slot_id]
  )
  output_schema(CHANGE_RESULT_SCHEMA)

  def call(signup_id:, slot_id:, override_rules: false)
    signup = ctx.find(Signup.all, signup_id)
    sheet = signup.signup_sheet
    not_found! unless ctx.allowed?(sheet, :show?)
    ctx.authorize!(signup, :move?)

    slot = ctx.find(sheet.signup_slots, slot_id)
    ctx.authorize!(signup, :override?) if override_rules

    from = signup.signup_slot
    signup.change!(by: ctx.person, slot: slot, override_rules: override_rules)
    changed!(signup) if from != slot
    SignupNotices.new.moved(signup, from: from, by: ctx.person) if from != slot

    roster_result(signup).merge(changed: from != slot)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end
end
