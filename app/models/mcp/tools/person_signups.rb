# A person's upcoming sign-ups. The person must be in policy_scope(Person)
# and PersonPolicy#show? must allow it, as for get_person. The sign-ups are
# those taken by the person or on their behalf, not cancelled, for events
# that haven't started, on sheets in policy_scope(SignupSheet) that
# SignupSheetPolicy#show? allows (archived sheets are left out). The sign-up
# pages never list a person's sign-ups, so each one is shown only where the
# sheet page would show it to this viewer: to the sheet's organizers
# (roster?, who also see on-behalf-of and notes); to someone it involves
# (they take it, made it, or it's on their behalf, as My sign-ups shows);
# and otherwise only when the sheet shows names to the viewer
# (SignupSheet#names_visible_to?), the sign-up is active or fulfilled, and
# the person is the one in the place (a slot lists the person, never whom
# it's on behalf of), and the slot isn't turned off (the page hides those).
# status goes to organizers and those involved only; the page lists active and
# fulfilled sign-ups alike to others. An event with no time set counts as
# upcoming for its whole day. Ordered by event start. Where unsure the
# sign-up is left out. signed_up_by is not returned: no sign-up page names who made a
# sign-up to anyone.
class Mcp::Tools::PersonSignups < Mcp::Tool
  include Mcp::Tools::SignupFormat

  tool_name "person_signups"
  description "A person's upcoming sign-ups (taken by them or on their behalf), soonest first, limited to those the sign-up " \
    "sheets show to you. on_behalf_of, where shown to you, is whose behalf the place is for, by default the person taking it."
  scope :read
  feature :signups
  input_schema(
    properties: { person_id: { type: "string", description: "Person ID (per_...)" }, limit: limit_property },
    required: [ "person_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            status: { type: "string", enum: %w[active cancelled fulfilled no_show] },
            sheet: SHEET_REF_SCHEMA,
            event: EVENT_SCHEMA,
            position: POSITION_SCHEMA,
            person: REF_SCHEMA,
            on_behalf_of: ON_BEHALF_OF_SCHEMA,
            answer: { type: %w[string null] },
            quantity: { type: %w[integer null] },
            note: { type: %w[string null] }
          },
          required: %w[id sheet event position person answer quantity]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(person_id:, limit: DEFAULT_LIMIT)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :show?)

    sheets = ctx.policy_scope(SignupSheet).visible
    signups = Signup.live.where(person_id: person.id).or(Signup.live.where(on_behalf_of_id: person.id))
    now = Time.current
    signups = signups.joins(signup_slot: %i[ event signup_position ]).where("events.start_time >= :now OR events.end_time >= :now", now: now)
      .where(signup_positions: { signup_sheet_id: sheets.select(:id) })
    includes = [ :person, :on_behalf_of, { signup_slot: [ :event, { signup_position: :signup_sheet } ] } ]

    sheet_ok = {}
    visible = signups.includes(*includes).select do |signup|
      sheet = signup.signup_sheet
      sheet_ok[sheet.id] = ctx.allowed?(sheet, :show?) unless sheet_ok.key?(sheet.id)
      upcoming?(signup.event, now) && sheet_ok[sheet.id] && shown?(signup, sheet, person)
    end

    list(Signup.where(id: visible.map(&:id)).joins(signup_slot: :event).includes(*includes).order("events.start_time", :created_at, :id), limit: limit) do |signup|
      signup_item(signup)
    end
  end

  private

  def shown?(signup, sheet, person)
    return true if ctx.allowed?(sheet, :roster?)
    return true if involved?(signup)

    (signup.active? || signup.fulfilled?) && signup.person_id == person.id && !signup.signup_slot.disabled? && sheet.names_visible_to?(ctx.person)
  end

  def signup_item(signup)
    sheet = signup.signup_sheet
    involved = involved?(signup)
    organizer = ctx.allowed?(sheet, :roster?)
    json = signup_json(signup, status: organizer || involved).merge(sheet: { id: sheet.neat_id, title: sheet.title }, event: event_json(signup.event),
      position: position_json(signup.signup_position))
    json[:on_behalf_of] = person_json(signup.on_behalf_of) if (organizer || involved) && signup.on_behalf_of && signup.on_behalf_of_id != signup.person_id
    json[:note] = signup.note.presence if organizer
    json
  end
end
