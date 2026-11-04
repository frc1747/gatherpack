# Changes a sign-up's details. The sheet must pass SignupSheetPolicy#show? (SignupsController
# line 75; an organizer always does). The pages split by who is asking, and this follows
# SignupPolicy#update?.
#
# With update? (the viewer's own or a relative's, active, sheet open, before the cutoff) it
# mirrors SignupsController#update (lines 47-64): quantity, answer, note and on_behalf_of_id,
# through Signup#change!. check_choices! (lines 116-125) is private to that controller, so its
# on-behalf-of half is reproduced here, as organizers pass Signup#change!'s own check: the
# person's half doesn't apply, as this tool doesn't change who takes the place.
# on_behalf_of_id blank is "Whoever takes the place" (line 51).
#
# Otherwise, with SignupPolicy#place?, it mirrors RosterSignupsController#update (lines
# 62-67; set_signup, line 138): quantity, answer and note. That page drops on_behalf_of_id,
# so this refuses it by name.
#
# A quantity on a people position is dropped by the member page (detail_params, line 153)
# and fails validation on the roster; this refuses it by name on both. What isn't sent stays
# as it is, as the pages' forms send the current values back. The closed schema refuses the
# forms' person_id by name, and leaves moving to move_signup.
#
# The result is what get_signup_sheet shows the viewer. An organizer gets the roster row.
# Anyone else gets on_behalf_of only if involved in the sign-up, as remove_signup does, and no
# note. Either comes back when the call just set it, so a client can confirm its own change.
class Mcp::Tools::UpdateSignup < Mcp::Tool
  include Mcp::Tools::SignupRosterFormat

  DETAILS = %w[quantity answer note on_behalf_of_id].freeze
  MAX_QUANTITY = 2_147_483_647

  tool_name "update_signup"
  description "Change a sign-up's quantity, answer, note or whose behalf it's on, as the sign-up's Change page or the roster's Edit does; only what you send changes. " \
    "You can change your own and those of people you may sign up, until the sheet's cutoff; an organizer can change any on their sheet, but on_behalf_of_id only on a sign-up that is also their own. " \
    "Anyone else in view gets \"Not allowed\", a sheet you can't see \"Not found\"."
  scope :write
  feature :signups
  mask_argument :answer, :note
  input_schema(
    properties: {
      signup_id: { type: "string", description: "The sign-up's ID (sup_)" },
      quantity: { type: "integer", minimum: 1, maximum: MAX_QUANTITY, description: "How many, on an item position only" },
      answer: { type: "string", description: "The answer to the position's question; an empty string clears it" },
      note: { type: "string", description: "A note for the organizers; an empty string clears it" },
      on_behalf_of_id: { type: %w[string null], description: "Whose behalf it's on (per_); null or empty for whoever takes the place" }
    },
    required: %w[signup_id],
    closed: true
  )
  output_schema(RESULT_SCHEMA)

  def call(signup_id:, **details)
    signup = ctx.find(Signup.all, signup_id)
    sheet = signup.signup_sheet
    not_found! unless ctx.allowed?(sheet, :show?)

    member = ctx.allowed?(signup, :update?)
    ctx.authorize!(signup, :place?) unless member

    invalid_argument!("Give at least one of #{DETAILS.to_sentence(last_word_connector: " or ")}") if details.empty?
    if details.key?(:on_behalf_of_id) && !member
      raise Mcp::NotAllowed, "Not allowed: on_behalf_of_id. The roster can't change whose behalf a sign-up is on"
    end
    invalid_argument!("quantity is only for item positions") if details.key?(:quantity) && !signup.signup_slot.items?

    changes = details.slice(:quantity, :answer, :note)
    changes[:on_behalf_of] = on_behalf_of(signup, sheet, details[:on_behalf_of_id]) if details.key?(:on_behalf_of_id)
    signup.assign_attributes(changes)
    check_on_behalf_of!(signup, sheet) if member

    signup.change!(by: ctx.person, **changes)
    changed!(signup)
    result(signup, sheet, details)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  # The form's choices, then anyone the viewer can see, whom check_on_behalf_of! then
  # refuses; anyone else is "Not found". The current one stays allowed, as the form keeps
  # it offered (signups/_form).
  def on_behalf_of(signup, sheet, id)
    return signup.person if id.blank?
    return signup.on_behalf_of if signup.on_behalf_of&.neat_id == id

    Mcp.find_by_neat_id(sheet.on_behalf_of_choices_for(ctx.person, signup.person), id) || ctx.find(Person, id)
  end

  def check_on_behalf_of!(signup, sheet)
    return unless signup.on_behalf_of_id_changed?
    return if sheet.on_behalf_of_choices_for(ctx.person, signup.person).exists?(id: signup.on_behalf_of_id)

    invalid_argument!("You can't sign up on behalf of #{signup.on_behalf_of.identifier_name}")
  end

  def result(signup, sheet, details)
    return roster_result(signup) if ctx.allowed?(sheet, :roster?)

    json = signup_json(signup, status: true).merge(signup_context(signup))
    json[:on_behalf_of] = person_json(signup.on_behalf_of || signup.person) if involved?(signup) || details.key?(:on_behalf_of_id)
    json[:note] = signup.note.presence if details.key?(:note)
    json
  end
end
