# One sign-up sheet as its page shows it (SignupSheetsController#show). The
# sheet must be in policy_scope(SignupSheet) and SignupSheetPolicy#show?
# must allow it. Events are the sheet's, oldest first, each with its slots
# (positions at that event, in position order); slots turned off are left
# out, as the page does. Every viewer gets each slot's cap, filled count and
# open places. Who holds the places follows the page: with names_visible
# (SignupSheet#names_visible_to?: organizers, or members of the audience
# while the sheet isn't a draft and names_permission is everyone) a slot
# lists its active and fulfilled sign-ups with the person, answer and
# quantity; otherwise slots list no sign-ups. Organizers (roster?) get the
# roster's view instead: every sign-up in any status, with who it is on
# behalf of (when not the person) and the organizer note. Others never see
# on-behalf-of or notes on a slot. my_signups are the viewer's own, as the
# page's My sign-ups card shows them: sign-ups the viewer takes, made, or
# that are on their behalf, not cancelled, with who it's for and who took it.
# Slot sign-ups are capped at `limit` (default 25, at most 100) per slot with
# signups_truncated.
class Mcp::Tools::GetSignupSheet < Mcp::Tool
  include Mcp::Tools::SignupFormat

  tool_name "get_signup_sheet"
  description "One sign-up sheet you can see: team, status, description, its events and, for each event, the positions with " \
    "capacity, filled and open places. Who holds each place is listed only where the sheet shows names to you " \
    "(organizers also see every status, on-behalf-of and notes). my_signups are yours."
  scope :read
  feature :signups
  input_schema(
    properties: { sheet_id: { type: "string", description: "The sheet's ID (sush_)" }, limit: limit_property.merge(description: "At most this many sign-ups per slot (default 25)") },
    required: [ "sheet_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      status: { type: "string", enum: %w[draft open closed archived] },
      team: REF_SCHEMA,
      description: { type: %w[string null] },
      contact: { type: %w[string null] },
      names_visible: { type: "boolean" },
      organizer: { type: "boolean" },
      events: {
        type: "array",
        items: {
          type: "object",
          properties: {
            event: EVENT_SCHEMA,
            slots: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  id: { type: "string" },
                  position: POSITION_SCHEMA,
                  capacity: { type: %w[integer null] },
                  filled: { type: "integer" },
                  open: { type: %w[integer null] },
                  full: { type: "boolean" },
                  signups: { type: "array", items: Mcp::Tools::SignupFormat::SIGNUP_SCHEMA },
                  signups_truncated: { type: "boolean" }
                },
                required: %w[id position capacity filled open full signups signups_truncated]
              }
            }
          },
          required: %w[event slots]
        }
      },
      my_signups: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            status: { type: "string" },
            event: EVENT_SCHEMA,
            position: POSITION_SCHEMA,
            person: REF_SCHEMA,
            on_behalf_of: REF_SCHEMA,
            signed_up_by: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            answer: { type: %w[string null] },
            quantity: { type: %w[integer null] }
          },
          required: %w[id status event position person on_behalf_of signed_up_by answer quantity]
        }
      }
    },
    required: %w[id title status team description contact names_visible organizer events my_signups]
  )

  def call(sheet_id:, limit: DEFAULT_LIMIT)
    sheet = ctx.find(SignupSheet, sheet_id)
    ctx.authorize!(sheet, :show?)

    viewer = ctx.person
    organizer = ctx.allowed?(sheet, :roster?)
    names_visible = sheet.names_visible_to?(viewer)
    limit = limit.to_i.clamp(1, MAX_LIMIT)
    events = sheet.events.order(:start_time, :id).to_a
    slots = sheet.signup_slots.where(disabled: false).includes(signup_position: :signup_position_rules, signups: %i[ person on_behalf_of ])
      .sort_by { |slot| [ slot.signup_position.position, slot.signup_position.created_at ] }.group_by(&:event_id)

    {
      id: sheet.neat_id,
      title: sheet.title,
      status: sheet.status,
      team: team_json(sheet.team),
      description: sheet.description.presence,
      contact: sheet.contact.presence,
      names_visible: names_visible,
      organizer: organizer,
      events: events.map { |event| { event: event_json(event), slots: slots.fetch(event.id, []).map { |slot| slot_json(slot, organizer, names_visible, limit) } } },
      my_signups: my_signups(sheet, viewer)
    }
  end

  private

  def slot_json(slot, organizer, names_visible, limit)
    shown = if organizer
      slot.signups.sort_by { |signup| [ signup.created_at, signup.id ] }
    elsif names_visible
      slot.signups.select { |signup| signup.active? || signup.fulfilled? }.sort_by { |signup| [ signup.created_at, signup.id ] }
    else
      []
    end

    {
      id: slot.neat_id,
      position: position_json(slot.signup_position),
      capacity: slot.capacity_value,
      filled: slot_used(slot),
      open: slot_open(slot),
      full: slot_open(slot)&.zero? || false,
      signups: shown.first(limit).map { |signup| organizer ? roster_json(signup) : signup_json(signup) },
      signups_truncated: shown.size > limit
    }
  end

  # The roster row: on behalf of only when it isn't the person, and the note.
  def roster_json(signup)
    json = signup_json(signup).merge(note: signup.note.presence)
    json[:on_behalf_of] = person_json(signup.on_behalf_of) if signup.on_behalf_of && signup.on_behalf_of_id != signup.person_id
    json
  end

  def my_signups(sheet, viewer)
    return [] if viewer.nil?

    signups = sheet.signups.live
    signups = signups.where(person_id: viewer.id).or(signups.where(signed_up_by_id: viewer.id)).or(signups.where(on_behalf_of_id: viewer.id))
    signups.includes(:person, :signed_up_by, :on_behalf_of, signup_slot: %i[ event signup_position ]).to_a
      .sort_by { |signup| [ signup.event.start_time, signup.signup_position.position, signup.created_at, signup.id ] }.map do |signup|
        signup_json(signup).except(:status, :person).merge(
          status: signup.status, event: event_json(signup.event), position: position_json(signup.signup_position),
          person: person_json(signup.person), on_behalf_of: person_json(signup.on_behalf_of || signup.person),
          signed_up_by: signup.signed_up_by && person_json(signup.signed_up_by)
        )
      end
  end
end
