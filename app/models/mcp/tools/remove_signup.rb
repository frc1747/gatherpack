# Cancels a sign-up, which stays on the roster as cancelled, through Signup#cancel! as
# both sign-up pages do, so the hooks and sign-up notifications run. The sheet must
# pass SignupSheetPolicy#show? (SignupsController line 75; an organizer always does).
#
# The pages leave the choice of path to the user; this tool takes the broader one open
# to the viewer. With SignupPolicy#place? it mirrors RosterSignupsController#destroy
# (lines 71-79): any sign-up on the sheet, past the cutoff too, and once cancelled the
# people on it get SignupNotices#cancelled. The page offers no choice about that email.
# Otherwise it mirrors SignupsController#destroy (lines 68-71): SignupPolicy#destroy?
# (line 81), which holds a member to cancel_cutoff_hours, and no email, as on that page.
#
# Against the pages: an organizer cancelling their own sign-up could use the member page,
# which sends no email; here they get the roster's.
#
# on_behalf_of is returned to organizers and to those involved in the sign-up. destroy?
# also lets someone cancel the sign-up of a person they could sign up. The edit page
# shows that viewer who it's on behalf of; the tool is narrower and withholds it, which
# is allowed (get_signup_sheet line 15).
# signed_up_by is not returned: neither sign-up page names who made a sign-up to anyone.
class Mcp::Tools::RemoveSignup < Mcp::Tool
  include Mcp::Tools::SignupFormat

  tool_name "remove_signup"
  description "Cancel a sign-up. It stays on the roster as cancelled. You can cancel your own and those of people you may sign up, until the " \
    "sheet's cutoff before the event. An organizer can cancel any sign-up on their sheet, past the cutoff too, and the people on it get an email. " \
    "Returns the cancelled sign-up; on_behalf_of, where shown to you, is whose behalf the place was for, by default the person who held it."
  scope :write
  feature :signups
  destructive
  input_schema(
    properties: { signup_id: { type: "string", description: "The sign-up's ID (sup_)" } },
    required: [ "signup_id" ]
  )
  output_schema(Mcp::Tools::PlaceSignup::RESULT_SCHEMA.merge(
    properties: Mcp::Tools::PlaceSignup::RESULT_SCHEMA[:properties].except(:signed_up_by),
    required: Mcp::Tools::PlaceSignup::RESULT_SCHEMA[:required] - %w[on_behalf_of signed_up_by]
  ))

  def call(signup_id:)
    signup = ctx.find(Signup.all, signup_id)
    not_found! unless ctx.allowed?(signup.signup_sheet, :show?)

    organizer = ctx.allowed?(signup, :place?)
    if organizer
      invalid_argument!("#{person_json(signup.person)[:name]}'s sign-up was already cancelled") if signup.cancelled?

      signup.cancel!
      SignupNotices.new.cancelled(signup, by: ctx.person) if signup.saved_change_to_status?
    else
      ctx.authorize!(signup, :destroy?)
      signup.cancel!
    end

    changed!(signup)
    json = signup_json(signup, status: true).merge(
      sheet: { id: signup.signup_sheet.neat_id, title: signup.signup_sheet.title },
      event: event_json(signup.event),
      position: position_json(signup.signup_position)
    )
    json[:on_behalf_of] = person_json(signup.on_behalf_of || signup.person) if organizer || involved?(signup)
    json
  end
end
