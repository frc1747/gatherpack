# Marks a sign-up, as the roster's Mark buttons do (RosterSignupsController#mark, lines
# 83-93): SignupPolicy#mark? (set_signup, line 138), a status of fulfilled, no_show or
# active (line 84), refused if the sign-up was cancelled (line 86) or for a no-show
# before the event starts (line 87), then update! (line 91), so the hooks run. On an
# item position fulfilled reads "Brought" and no_show "Not brought". The sheet must pass
# SignupSheetPolicy#show? or the sign-up is "Not found": the roster has no such step, but
# refuses all the same at mark?.
#
# The controller takes any of the three from any status other than cancelled, though the
# page's buttons offer only Fulfilled and No-show on an active sign-up and Undo otherwise.
# This follows the controller. Marking it with the status it already has does what the
# page does: it saves nothing new. Here the result says changed: false, so a repeated
# call is safe to retry.
class Mcp::Tools::MarkSignup < Mcp::Tool
  include Mcp::Tools::SignupRosterFormat

  tool_name "mark_signup"
  description "Mark a sign-up fulfilled (\"Brought\" for items), no_show (\"Not brought\" for items, once the event has started) or back to active, as the roster's " \
    "Mark buttons do: you get \"Not allowed\" on a sheet you don't organize or for your own family's sign-up, \"Not found\" for a sheet you can't see. " \
    "Marking it with the status it already has changes nothing and returns changed: false."
  scope :write
  feature :signups
  input_schema(
    properties: {
      signup_id: { type: "string", description: "The sign-up's ID (sup_)" },
      status: { type: "string", enum: %w[fulfilled no_show active], description: "fulfilled, no_show or active" }
    },
    required: %w[signup_id status]
  )
  output_schema(CHANGE_RESULT_SCHEMA)

  def call(signup_id:, status:)
    signup = ctx.find(Signup.all, signup_id)
    not_found! unless ctx.allowed?(signup.signup_sheet, :show?)
    ctx.authorize!(signup, :mark?)

    invalid_argument!("This sign-up was cancelled") if signup.cancelled?
    invalid_argument!("Mark no-shows once the event has started") if status == "no_show" && signup.event.start_time > Time.current

    before = signup.status
    signup.update!(status: status)
    changed!(signup)

    roster_result(signup).merge(changed: before != status)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end
end
