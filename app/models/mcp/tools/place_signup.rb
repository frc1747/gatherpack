# Signs a person up for a slot, through Signup.place! as both sign-up pages do, so
# the slot's row lock, capacity, rules, confirmation emails, reminder and hooks all
# run. The sheet must pass SignupSheetPolicy#show? (SignupsController line 75; an
# organizer always does).
#
# The pages leave the choice of path to the user; this tool takes the broader one
# open to the viewer. With SignupPolicy#place? it mirrors RosterSignupsController#create
# (lines 27-59): anyone in sheet.audience (line 30), on a draft or closed sheet too, in
# any slot of the sheet, where Signup.place! refuses one turned off. Otherwise it
# mirrors SignupsController#create (lines 26-40): SignupPolicy#create? (line 30), which
# covers check_choices! (line 116) as the sign-up is always on the taker's own behalf,
# and only slots still on (find_slot, line 84).
#
# Narrower than the pages: no rule override, so a failing rule comes back as an invalid
# argument even for an organizer (the roster's override_rules box); the sign-up is on
# the taker's own behalf (no on_behalf_of_id, the default of both forms); and there is
# no quantity or answer, so an item position or one with a required question comes back
# as an invalid argument, as an empty form does.
#
# Also narrower: an exact repeat is refused, where the pages place the person again. A
# client that lost a response or repeats a call can't see the sheet the way a person
# does, and a repeat would send every email twice and could take the last place from
# someone else. A repeat is an active sign-up in the slot with the same person and
# on-behalf-of, made by the viewer. Only the viewer's own count, so a refusal can't reveal
# someone else's place on a sheet that hides names; one made by someone else still goes
# through, as on the page. The check is inside the slot's lock, so parallel repeats can't
# pass it together.
#
# A person is looked up among those the viewer could sign up, or else in
# policy_scope(Person): someone the viewer can't see is "Not found", whatever their
# place on the sheet. A ward needn't be in the guardian's person scope to be signed up,
# nor anyone in the audience in the organizer's, as the pages don't ask that either.
# No read tool lists the audience, so an organizer can place an audience member outside
# their person scope only if they already have the ID. The roster form lists them all.
#
# The result names who made the sign-up (signed_up_by, always the viewer here) beside
# the person taking it and on_behalf_of, so a client can't read on_behalf_of as the actor.
class Mcp::Tools::PlaceSignup < Mcp::Tool
  include Mcp::Tools::SignupFormat

  RESULT_SCHEMA = {
    type: "object",
    properties: Mcp::Tools::SignupFormat::SIGNUP_SCHEMA[:properties].merge(
      signed_up_by: Mcp::Tools::SignupFormat::SIGNED_UP_BY_SCHEMA,
      sheet: Mcp::Tools::SignupFormat::SHEET_REF_SCHEMA,
      event: Mcp::Tools::SignupFormat::EVENT_SCHEMA,
      position: Mcp::Tools::SignupFormat::POSITION_SCHEMA
    ),
    required: %w[id status person signed_up_by on_behalf_of answer quantity sheet event position]
  }.freeze

  tool_name "place_signup"
  description "Sign a person up for a slot on a sign-up sheet: yourself or someone you may sign up, or anyone the sheet is open to if you " \
    "organize it. Capacity and the position's rules always apply, and no one can override a rule here. Positions for items or with a required " \
    "question can't be taken here. Unlike the sign-up pages, this refuses an exact repeat of an active sign-up you made in the slot. " \
    "Everyone on the sign-up gets the usual email. Returns the new sign-up: person is who takes the place, signed_up_by is you, and " \
    "on_behalf_of is whose behalf it is for, which here is the person taking it."
  scope :write
  feature :signups
  input_schema(
    properties: {
      slot_id: { type: "string", description: "The slot's ID (susl_), from get_signup_sheet" },
      person_id: { type: "string", description: "The ID of the person taking the place (per_)" }
    },
    required: %w[slot_id person_id]
  )
  output_schema(RESULT_SCHEMA)

  def call(slot_id:, person_id:)
    slot = ctx.find(SignupSlot.all, slot_id)
    sheet = slot.signup_sheet
    not_found! unless ctx.allowed?(sheet, :show?)

    organizer = ctx.allowed?(Signup.new(signup_slot: slot), :place?)
    not_found! if slot.disabled? && !organizer

    reach = organizer ? sheet.audience : sheet.takers_for(ctx.person)
    person = Mcp.find_by_neat_id(reach, person_id) || ctx.find(Person, person_id)
    if organizer
      invalid_argument!("Person must be someone the sheet is open to") unless sheet.open_to?(person)
    else
      ctx.authorize!(Signup.new(signup_slot: slot, person: person, signed_up_by: ctx.person, on_behalf_of: person), :create?)
    end

    signup = slot.with_lock do
      if slot.signups.active.exists?(person_id: person.id, on_behalf_of_id: person.id, signed_up_by_id: ctx.person.id)
        invalid_argument!("You already signed up #{person_json(person)[:name]} for this slot")
      end

      Signup.place!(slot: slot, person: person, signed_up_by: ctx.person, on_behalf_of: person)
    end

    changed!(signup)
    signup_result(signup)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  def signup_result(signup)
    signup_json(signup, status: true).merge(
      signed_up_by: (person_json(signup.signed_up_by) if signup.signed_up_by),
      on_behalf_of: person_json(signup.on_behalf_of),
      sheet: { id: signup.signup_sheet.neat_id, title: signup.signup_sheet.title },
      event: event_json(signup.event),
      position: position_json(signup.signup_position)
    )
  end
end
