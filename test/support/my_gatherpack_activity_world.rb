require_relative "checklists_world"

# The checklists fixture world (see ChecklistsWorld) with a season of
# activity for member, on 2026-11-15 (the 2026–27 season, from May 1):
#
#   Outreach: two timed check-ins (3 h each), counted by "Outreach events",
#             a count item on "Fall Requirements", which covers Members
#   Build: one all-day check-in, which no checklist covering member counts
#   Meeting: a meeting (an event on a time clock period) and a 2 h punch
#   Last season: one Outreach check-in in March 2026
#
# "Crew Trip" covers only member2 and has a count item counting Build, so
# member must never see its title or its item.
module MyGatherpackActivityWorld
  include ChecklistsWorld

  NOW = Time.utc(2026, 11, 15, 17)

  def build_activity_world
    build_checklists_world
    @outreach = EventType.create!(name: "Outreach")
    @build = EventType.create!(name: "Build")
    @meeting_type = EventType.create!(name: "Meeting")
    @period = TimeClockPeriod.create!(name: "Fall meetings", start_time: Date.new(2026, 9, 1), end_time: Date.new(2027, 6, 30),
      permission: :added_by_admin)

    @outreach1 = create_activity_event("Food drive", "2026-10-03 10:00", @outreach, location: "Town Hall")
    @outreach2 = create_activity_event("Library demo", "2026-10-17 10:00", @outreach)
    @build_day = Event.create!(name: "Build day", time_kind: "all_day", event_date: Date.new(2026, 9, 12), event_type: @build, team: @members)
    @meeting = create_activity_event("Tuesday meeting", "2026-10-06 18:00", @meeting_type, hours: 2, time_clock_period: @period)
    @last_season = create_activity_event("Spring fair", "2026-03-01 10:00", @outreach)

    [ @outreach1, @outreach2, @build_day, @meeting, @last_season ].each { |event| Checkin.create!(person: person(:member), event: event) }
    TimeClockPunch.create!(person: person(:member), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-06 18:00"), end_time: Time.zone.parse("2026-10-06 20:00"))

    @requirements = create_world_checklist("Fall Requirements")
    add_rule(@requirements, :include, :team, team: @members)
    @outreach_item = add_counting_item(@requirements, "Outreach events", @outreach)

    @crew_trip = create_world_checklist("Crew Trip")
    add_rule(@crew_trip, :include, :person, person_id: person(:member2).id)
    add_counting_item(@crew_trip, "Build shifts", @build)

    refresh(@requirements)
    refresh(@crew_trip)
  end

  def add_counting_item(checklist, label, event_type)
    item = checklist.checklist_items.new(kind: "count", label: label)
    item.config_params = { base_amount: 2, unit: "events" }
    item.save!
    item.commitment.commitment_sources.create!(kind: "checkins", subject: event_type)
    item
  end

  # Two Concessions events the person (on behalf of themselves, or of
  # on_behalf_of) signed up for and was marked done at, without checking in:
  # "Stocking" on a sheet that "Concessions shifts", a count item on Fall
  # Requirements, counts; "Shelving" on a sheet nothing counts. Guardians
  # may sign up their wards on both. Returns [stocking, shelving].
  def build_concessions_signups(name = :member, on_behalf_of: name, read_level: nil)
    concessions = EventType.create!(name: "Concessions")
    events = [ [ "Stocking", "2026-10-10 09:00" ], [ "Shelving", "2026-10-11 09:00" ] ].map do |title, start_time|
      event = create_activity_event(title, start_time, concessions)
      sheet = SignupSheet.create!(title: "#{title} crew", team: @members, status: :open,
        on_behalf_of_mode: :related_people, others_relationship_type_ids: [ @parent_of.id ])
      sheet.signup_sheet_events.create!(event: event)
      position = sheet.signup_positions.create!(name: "Helper", capacity: 5)
      Signup.create!(signup_slot: position.signup_slots.find_by!(event: event), person: person(name), on_behalf_of: person(on_behalf_of),
        signed_up_by: person(name), status: :fulfilled)
      [ event, sheet ]
    end
    item = @requirements.checklist_items.new(kind: "count", label: "Concessions shifts", read_level: read_level)
    item.config_params = { base_amount: 2, unit: "shifts" }
    item.save!
    item.commitment.commitment_sources.create!(kind: "signups", subject: events.first.last)
    refresh(@requirements)
    events.map(&:first)
  end

  def create_activity_event(name, start_time, event_type, hours: 3, team: @members, **attributes)
    start_time = Time.zone.parse(start_time)
    Event.create!(name: name, start_time: start_time, end_time: start_time + hours.hours, event_type: event_type, team: team, **attributes)
  end

  def activity_flags
    { feature_my_gatherpack: "true", feature_my_gatherpack_activity: "true", feature_checklists: "true", feature_events: "true",
      feature_signups: "true", feature_forms: "true" }
  end
end
