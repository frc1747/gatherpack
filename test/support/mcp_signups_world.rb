# Sign-up sheets for the MCP sign-up tool tests, on top of McpWorld:
#
#   include McpWorld
#   include McpSignupsWorld   # after McpWorld, so its settings are undone first
#
# Call build_mcp_world and then build_mcp_signups_world. Sign-up Sheets and
# Badges are turned on for each test, with the "Sheet Organizer" badge as an
# organizer grant. Tests travel_to MCP_SIGNUPS_NOW.
#
#   organizer: in Alpha with the grant badge, listed on the Bake Sale
#   "Bake Sale" (Alpha, open, names for everyone, sign up for related people
#   through Parent of): events Past Sale (3/10), Bake Day (3/14) and Clean-up
#   (3/15), positions Cashier (2 places) and Cookies (5 dozen, asks "Flavor?").
#     Bake Day Cashier: alpha_member (note "Bring change"), ward (signed up by guardian)
#     Bake Day Cookies: alpha_member for ward, 2 dozen "Oat"
#     Clean-up Cashier: alpha_manager (cancelled)
#     Past Sale Cashier: alpha_member
#   "Quiet Sale" (Alpha, open, names for organizers only): alpha_member, Cashier at Bake Day
#   "Draft Sale", "Closed Sale" (Alpha) and "Old Sale" (archived): no sign-ups
#   "Beta Sale" (Beta, open): beta_member, Cashier at Beta Day (3/16)
module McpSignupsWorld
  MCP_SIGNUPS_NOW = Time.utc(2026, 3, 12, 12, 0)

  def self.included(base)
    base.setup { @restore_signups_feature = apply_settings(feature_signups: "true", feature_badges: "true", signups_organizers: "Sheet Organizer") }
    base.teardown { @restore_signups_feature&.call }
  end

  def build_mcp_signups_world
    @people[:organizer] = create_world_person("Organizer", @alpha)
    @organizer_badge = create_world_badge("Sheet Organizer")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:organizer))

    @past_event = create_signups_event("Past Sale", @alpha, Time.utc(2026, 3, 10, 10, 0))
    @bake_day = create_signups_event("Bake Day", @alpha, Time.utc(2026, 3, 14, 10, 0))
    @cleanup = create_signups_event("Clean-up", @alpha, Time.utc(2026, 3, 15, 10, 0))
    @beta_day = create_signups_event("Beta Day", @beta, Time.utc(2026, 3, 16, 10, 0))

    @sheet = create_signups_sheet("Bake Sale", @alpha, [ @past_event, @bake_day, @cleanup ], created_by: person(:organizer),
      description: "Bring a smile", contact: "organizer@example.com", others_relationship_type_ids: [ @parent_of.id ], on_behalf_of_mode: :related_people)
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 2, description: "Takes the money")
    @cookies = @sheet.signup_positions.create!(name: "Cookies", kind: :items, unit: "dozen", capacity: 5, question: "Flavor?")
    @bake_day_cashier = create_signup(@cashier, :alpha_member, @bake_day, note: "Bring change")
    @ward_cashier = create_signup(@cashier, :ward, @bake_day, signed_up_by: person(:guardian))
    @ward_cookies = create_signup(@cookies, :alpha_member, @bake_day, on_behalf_of: person(:ward), quantity: 2, answer: "Oat")
    @cancelled = create_signup(@cashier, :alpha_manager, @cleanup, status: :cancelled)
    @past_signup = create_signup(@cashier, :alpha_member, @past_event)

    @quiet_sheet = create_signups_sheet("Quiet Sale", @alpha, [ @bake_day ], names_permission: :organizers)
    @quiet_sheet.signup_positions.create!(name: "Helper")
    @quiet_signup = create_signup(@quiet_sheet.signup_positions.first, :alpha_member, @bake_day)

    @draft_sheet = create_signups_sheet("Draft Sale", @alpha, [ @bake_day ], status: :draft)
    @closed_sheet = create_signups_sheet("Closed Sale", @alpha, [ @bake_day ], status: :closed)
    @archived_sheet = create_signups_sheet("Old Sale", @alpha, [ @bake_day ], status: :archived)
    [ @draft_sheet, @closed_sheet, @archived_sheet ].each { |sheet| sheet.signup_positions.create!(name: "Helper") }

    @beta_sheet = create_signups_sheet("Beta Sale", @beta, [ @beta_day ])
    @beta_sheet.signup_positions.create!(name: "Greeter", capacity: 3)
    @beta_signup = create_signup(@beta_sheet.signup_positions.first, :beta_member, @beta_day)
  end

  def create_signups_event(name, team, start_time)
    Event.create!(name: name, team: team, start_time: start_time, end_time: start_time + 2.hours, event_type: event_types(:one))
  end

  def create_signups_sheet(title, team, events, status: :open, **attributes)
    sheet = SignupSheet.create!(title: title, team: team, status: status, **attributes)
    events.each { |event| sheet.signup_sheet_events.create!(event: event) }
    sheet
  end

  # Places a sign-up directly, skipping the checks, for setups.
  def create_signup(position, name, event, status: :active, **attributes)
    attributes[:quantity] ||= 1 if position.items?
    slot = position.signup_slots.find_by!(event: event)
    Signup.create!(signup_slot: slot, person: person(name), signed_up_by: attributes.delete(:signed_up_by) || person(name), status: status, **attributes)
  end
end
