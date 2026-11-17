# The activity page (feature/my-gatherpack-activity) for Ella (member@):
# check-ins at five events of three types this season (two Workdays, two
# Outreach, one all-day Training), meeting punches this season and last (two
# of this season's three crew meetings), and one Outreach check-in last season. "What you've done" shows the
# meetings line and a section per kind of event, the season select shows
# something, and Home's "Also this season" lists the event types (no
# checklist covering Ella counts them).
#
# Dates follow MyGatherpack::Season (Settings[:my_gatherpack_season_start],
# May 1 by default), so this season's records stay in this season. Events
# and punches are found by name or note, so reloading moves them.
Hbr::SampleData.feature "feature/my-gatherpack-activity" do |s|
  s.enable_feature :my_gatherpack
  s.enable_feature :my_gatherpack_activity
  admin = s.login(:admin)
  ella = s.login!(:member, "member", "Ella", "Brown")
  facilities = s.team(:facilities)
  season = MyGatherpack::Season.containing(s.clock.today)
  last_season = MyGatherpack::Season.containing(season.starts_on - 1)
  # Days since the season started: this season's records fall between then and yesterday.
  span = [ (s.clock.today - season.starts_on).to_i, 1 ].max
  within = ->(share) { [ (span * share).floor, 1 ].max }

  workday = EventType.find_or_create_by!(name: "Workday")
  outreach = EventType.find_or_create_by!(name: "Outreach")
  training = EventType.find_or_create_by!(name: "Training")
  event = lambda do |name, type, start_time, hours: 3|
    s.upsert!(Event, { name: name }, event_type: type, team: facilities, location: "Community Hall", time_kind: "timed",
      start_time: start_time, end_time: start_time + hours.hours)
  end

  checked_in = [
    event.call("Activity: Fall Cleanup Workday", workday, s.clock.days_ago(within.(0.8), hour: 9)),
    event.call("Activity: Tool Shed Workday", workday, s.clock.days_ago(within.(0.3), hour: 9), hours: 4),
    event.call("Activity: Library Fair Booth", outreach, s.clock.days_ago(within.(0.6), hour: 10), hours: 2),
    event.call("Activity: Food Drive", outreach, s.clock.days_ago(within.(0.2), hour: 10)),
    s.upsert!(Event, { name: "Activity: Safety Training Day" }, event_type: training, team: facilities, location: "Community Hall",
      time_kind: "all_day", event_date: s.clock.date(-within.(0.5))),
    event.call("Activity: Spring Open House", outreach, (last_season.starts_on + 30).in_time_zone.change(hour: 10))
  ]
  checked_in.each { |record| Checkin.find_or_create_by!(event: record, person: ella) }

  meetings = s.upsert!(TimeClockPeriod, { name: "Facilities Crew Meetings" }, team: facilities,
    start_time: last_season.starts_on, end_time: season.ends_on, permission: "added_by_admin")
  TimeClockPunch.where(note: "Sample activity").delete_all
  punch = ->(start_time, hours) { TimeClockPunch.create!(person: ella, time_clock_period: meetings, start_time: start_time, end_time: start_time + hours.hours, note: "Sample activity", created_by: admin) }
  [ 0.9, 0.7, 0.4, 0.1 ].each { |share| punch.call(s.clock.days_ago(within.(share), hour: 18), 2) }
  # Three crew meetings this season; Ella's punches cover the first two.
  meeting_type = EventType.find_or_create_by!(name: "Meeting")
  [ 0.9, 0.7, 0.55 ].each_with_index do |share, index|
    starts = s.clock.days_ago(within.(share), hour: 18)
    s.upsert!(Event, { name: "Activity: Crew Meeting #{index + 1}" }, event_type: meeting_type, team: facilities, time_clock_period: meetings,
      location: "Community Hall", time_kind: "timed", start_time: starts, end_time: starts + 2.hours)
  end
  [ 40, 60, 80 ].each { |days| punch.call((last_season.starts_on + days).in_time_zone.change(hour: 18), 2) }

  activity = MyGatherpack::Activity.new(ella, season: season)
  s.report "Ella (member@) has check-ins at three event types and meeting punches this season and last"
  # Other layers (commitments' Crew Shifts) can add kinds of their own.
  s.expect("Ella's season has three kinds of event and meetings") { (%w[Meetings Outreach Training Workday] - activity.kind_rows.map(&:name)).empty? }
  s.expect("Ella came to two of three crew meetings") { [ activity.meetings_attended, activity.meetings_held.size ] == [ 2, 3 ] }
  s.expect("Training is all-day, so it has no hours") { activity.kind_row(training.neat_id)&.hours.nil? }
  s.expect("What you've done has Outreach, Training and Workday sections") { (%w[Outreach Training Workday] - activity.done_sections.map(&:name)).empty? }
  s.expect("Workday lists its two events, newest first") do
    names = activity.done_sections.find { |section| section.key == workday.neat_id }&.lines&.map { |line| line.event.name } || []
    names & [ "Activity: Tool Shed Workday", "Activity: Fall Cleanup Workday" ] == [ "Activity: Tool Shed Workday", "Activity: Fall Cleanup Workday" ]
  end
  s.expect("meetings are one line, not a section") { activity.meetings_row && activity.done_sections.none? { |section| section.name == "Meeting" } }
  s.expect("the season select offers last season too") { activity.seasons.include?(last_season) }
  s.expect("Home lists the event types no checklist counts") { MyGatherpack::Activity.uncounted(ella, season).any? }
end
