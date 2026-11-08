# One sign-up sheet as its page shows it (SignupSheetsController#show). The
# sheet must be in policy_scope(SignupSheet) and SignupSheetPolicy#show?
# must allow it. Events are the sheet's, oldest first (from, YYYY-MM-DD, starts
# at that day; it also starts my_signups there), each with its slots (positions at that event, in position
# order); slots turned off are left out, as the page does. Every viewer gets
# each slot's cap, filled count and open places. Who holds the places follows
# the page: with names_visible (SignupSheet#names_visible_to?: organizers, or
# members of the audience while the sheet isn't a draft and names_permission
# is everyone) a slot lists its active and fulfilled sign-ups with the person,
# answer and quantity, and no status, as the page lists them alike (a person
# gets the status of sign-ups they're involved in); otherwise slots list no
# sign-ups. Organizers (roster?) get the roster's view instead: every sign-up
# in any status, with who it is on behalf of (when not the person) and the
# organizer note, and slots turned off that still hold sign-ups, with
# disabled: true. Others never see on-behalf-of or notes
# on a slot. my_signups are the viewer's own, as the page's My sign-ups
# card shows them: sign-ups the viewer takes, made, or that are on their
# behalf (placing someone from the roster doesn't count as making theirs), not cancelled, with status and who it's for, but not who made it
# (neither the sign-up pages nor the roster print that, so signed_up_by is never returned). `limit` (default 25, at most 100) caps the
# events, each slot's sign-ups and my_signups, each with a truncated flag.
class Mcp::Tools::GetSignupSheet < Mcp::Tool
  include Mcp::Tools::SignupFormat

  tool_name "get_signup_sheet"
  description "One sign-up sheet you can see: team, status, description, its events and, for each event, the positions with " \
    "capacity, filled and open places (`from` and `limit` page through events and my_signups). Who holds each place is listed only where the " \
    "sheet shows names to you (organizers also see every status, on-behalf-of, notes and turned-off slots). on_behalf_of is whose behalf " \
    "the place is for, by default the person taking it. my_signups are yours."
  scope :read
  feature :signups
  input_schema(
    properties: {
      sheet_id: { type: "string", description: "The sheet's ID (sush_)" },
      from: { type: "string", description: "Only events starting on or after this day, YYYY-MM-DD, to read a long sheet in pieces" },
      limit: limit_property.merge(description: "At most this many events, sign-ups per slot and of my_signups (default 25)")
    },
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
                  disabled: { type: "boolean" },
                  signups: { type: "array", items: Mcp::Tools::SignupFormat::SIGNUP_SCHEMA },
                  signups_truncated: { type: "boolean" }
                },
                required: %w[id position capacity filled open full disabled signups signups_truncated]
              }
            }
          },
          required: %w[event slots]
        }
      },
      events_truncated: { type: "boolean" },
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
            on_behalf_of: ON_BEHALF_OF_SCHEMA,
            answer: { type: %w[string null] },
            quantity: { type: %w[integer null] }
          },
          required: %w[id status event position person on_behalf_of answer quantity]
        }
      },
      my_signups_truncated: { type: "boolean" }
    },
    required: %w[id title status team description contact names_visible organizer events events_truncated my_signups my_signups_truncated]
  )

  def call(sheet_id:, from: nil, limit: DEFAULT_LIMIT)
    sheet = ctx.find(SignupSheet, sheet_id)
    ctx.authorize!(sheet, :show?)

    viewer = ctx.person
    organizer = ctx.allowed?(sheet, :roster?)
    names_visible = sheet.names_visible_to?(viewer)
    limit = limit.to_i.clamp(1, MAX_LIMIT)
    events = sheet.events.order(:start_time, :id)
    since = from && parse_date(from).in_time_zone.beginning_of_day
    events = events.where(start_time: since..) if since
    events = events.limit(limit + 1).to_a
    shown_events = events.first(limit)
    slots = sheet.signup_slots.where(event_id: shown_events.map(&:id)).includes(signup_position: :signup_position_rules, signups: %i[ person on_behalf_of ])
      .select { |slot| !slot.disabled? || (organizer && slot.signups.any?) }
      .sort_by { |slot| [ slot.signup_position.position, slot.signup_position.created_at ] }.group_by(&:event_id)
    mine, mine_truncated = my_signups(sheet, viewer, limit, since)

    {
      id: sheet.neat_id,
      title: sheet.title,
      status: sheet.status,
      team: team_json(sheet.team),
      description: sheet.description.presence,
      contact: sheet.contact.presence,
      names_visible: names_visible,
      organizer: organizer,
      events: shown_events.map { |event| { event: event_json(event), slots: slots.fetch(event.id, []).map { |slot| slot_json(slot, organizer, names_visible, limit) } } },
      events_truncated: events.size > limit,
      my_signups: mine,
      my_signups_truncated: mine_truncated
    }
  end

  private

  def parse_date(value)
    raise Date::Error unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    invalid_argument!("from must be a date like 2026-03-31")
  end

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
      disabled: slot.disabled?,
      signups: shown.first(limit).map { |signup| organizer ? roster_json(signup) : signup_json(signup, status: involved?(signup)) },
      signups_truncated: shown.size > limit
    }
  end

  # The roster row: status, on behalf of only when it isn't the person, and the note.
  def roster_json(signup)
    json = signup_json(signup, status: true).merge(note: signup.note.presence)
    json[:on_behalf_of] = person_json(signup.on_behalf_of) if signup.on_behalf_of && signup.on_behalf_of_id != signup.person_id
    json
  end

  # The viewer's first `limit` sign-ups for events starting at or after since
  # (when given), and whether there are more.
  def my_signups(sheet, viewer, limit, since)
    return [ [], false ] if viewer.nil?

    signups = sheet.signups.live
    signups = signups.where(person_id: viewer.id).or(signups.where(on_behalf_of_id: viewer.id))
      .or(signups.where(signed_up_by_id: viewer.id, placed_by_organizer: false))
    signups = signups.joins(signup_slot: :event).where(events: { start_time: since.. }) if since
    sorted = signups.includes(:person, :on_behalf_of, signup_slot: %i[ event signup_position ]).to_a
      .sort_by { |signup| [ signup.event.start_time, signup.signup_position.position, signup.created_at, signup.id ] }
    items = sorted.first(limit).map do |signup|
      signup_json(signup, status: true).merge(
        event: event_json(signup.event), position: position_json(signup.signup_position),
        on_behalf_of: person_json(signup.on_behalf_of || signup.person)
      )
    end
    [ items, sorted.size > limit ]
  end
end
