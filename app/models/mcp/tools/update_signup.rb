# Changes a sign-up's details. The sheet must pass SignupSheetPolicy#show? (SignupsController
# line 75; an organizer always does). The pages split by who is asking, and this follows
# SignupPolicy#update?.
#
# With update? (the viewer's own or a relative's, active, sheet open, before the cutoff) it
# mirrors SignupsController#update (lines 47-64): quantity, answer, note, person_id and
# on_behalf_of_id, through Signup#change!, which checks the new taker's rules and the slot.
# Lines 49-53 and check_choices! (lines 116-125) are private to that controller, so they are
# reproduced here, as organizers pass Signup#change!'s own check. on_behalf_of_id blank is
# "Whoever takes the place" (line 51), and a new taker with no on_behalf_of_id takes that too
# (lines 52-53). The page ignores a blank person_id (line 49); this refuses it by name.
#
# Otherwise, with SignupPolicy#place?, it mirrors RosterSignupsController#update (lines
# 62-67; set_signup, line 138): quantity, answer and note. That page drops person_id and
# on_behalf_of_id, so this refuses them by name.
#
# A quantity on a people position is dropped by the member page (detail_params, line 153)
# and fails validation on the roster; this refuses it by name on both. What isn't sent stays
# as it is, as the pages' forms send the current values back. move_signup changes the slot.
#
# The result is what get_signup_sheet shows the viewer. An organizer gets the roster row.
# Anyone else gets on_behalf_of only if involved in the sign-up, as remove_signup does, and no
# note. Either comes back when the call just set it, so a client can confirm its own change.
class Mcp::Tools::UpdateSignup < Mcp::Tool
  include Mcp::Tools::SignupRosterFormat

  DETAILS = %w[quantity answer note person_id on_behalf_of_id].freeze
  MAX_QUANTITY = 2_147_483_647

  tool_name "update_signup"
  description "Change a sign-up's quantity, answer, note, who takes the place or whose behalf it's on, as the sign-up's Change page or the roster's Edit does; only what you send changes. " \
    "You can change your own and those of people you may sign up, until the sheet's cutoff; an organizer can change any on their sheet, but person_id and on_behalf_of_id only on a sign-up they could change on the Change page. " \
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
      person_id: { type: "string", description: "Who takes the place (per_): yourself or someone you may sign up. Unless on_behalf_of_id is sent, it's then on their behalf" },
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
    unless member
      refused = details.keys & %i[ person_id on_behalf_of_id ]
      raise Mcp::NotAllowed, "Not allowed: #{refused.to_sentence}. The roster can't change who takes a sign-up or whose behalf it's on" if refused.any?
    end
    invalid_argument!("person_id can't be blank") if details.key?(:person_id) && details[:person_id].blank?
    invalid_argument!("quantity is only for item positions") if details.key?(:quantity) && !signup.signup_slot.items?

    changes = details.slice(:quantity, :answer, :note)
    changes[:person] = taker(signup, sheet, details[:person_id]) if details.key?(:person_id)
    if details.key?(:on_behalf_of_id)
      changes[:on_behalf_of] = on_behalf_of(signup, sheet, details[:on_behalf_of_id], changes[:person] || signup.person)
    elsif changes[:person] && changes[:person] != signup.person
      changes[:on_behalf_of] = changes[:person]
    end
    signup.assign_attributes(changes)
    check_choices!(signup, sheet) if member

    signup.change!(by: ctx.person, **changes)
    changed!(signup)
    result(signup, sheet, details)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  # The form's choices, then anyone the viewer can see, whom check_choices! then refuses;
  # anyone else is "Not found". The current one stays allowed, as the form keeps it offered
  # (signups/_form).
  def taker(signup, sheet, id)
    return signup.person if signup.person.neat_id == id

    Mcp.find_by_neat_id(sheet.takers_for(ctx.person), id) || ctx.find(Person, id)
  end

  def on_behalf_of(signup, sheet, id, taker)
    return taker if id.blank?
    return signup.on_behalf_of if signup.on_behalf_of&.neat_id == id

    Mcp.find_by_neat_id(sheet.on_behalf_of_choices_for(ctx.person, taker), id) || ctx.find(Person, id)
  end

  # SignupsController#check_choices!, for a sign-up that already exists.
  def check_choices!(signup, sheet)
    new_taker = signup.person_id_changed?
    problems = []
    problems << "You can't sign up #{signup.person.identifier_name} on this sheet" if new_taker && !sheet.takers_for(ctx.person).exists?(id: signup.person_id)
    if (new_taker || signup.on_behalf_of_id_changed?) && !sheet.on_behalf_of_choices_for(ctx.person, signup.person).exists?(id: signup.on_behalf_of_id)
      problems << "You can't sign up on behalf of #{signup.on_behalf_of.identifier_name}"
    end
    invalid_argument!(problems.to_sentence) if problems.any?
  end

  def result(signup, sheet, details)
    return roster_result(signup) if ctx.allowed?(sheet, :roster?)

    json = signup_json(signup, status: true).merge(signup_context(signup))
    json[:on_behalf_of] = person_json(signup.on_behalf_of || signup.person) if involved?(signup) || details.key?(:on_behalf_of_id)
    json[:note] = signup.note.presence if details.key?(:note)
    json
  end
end
