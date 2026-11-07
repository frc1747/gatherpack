# Adds an Attendance item to "Trip Eligibility" (feature/checklists) with
# six Youth Meetings in a "Youth Program Meetings" time clock period on the
# Youth Program (the item counts periods of the checklist's team and below,
# so the base season period on the top team isn't used), five days apart,
# the last one two days ago (the season starts at least 28 days back). Two rules
# counted together: "Autumn" (20% of meeting hours, from the season's start
# until 15 days ago) and "Winter" (40%, since then).
#
# - Chloe came to every meeting: done.
# - Grace came to three and is excused from one she missed (by the admin,
#   with a reason): done, with "Excused from ..." in the detail.
# - Kate came to one and left early: Below minimum.
# - Sam punched in only outside meeting time: Not yet (extra hours don't
#   count on this item).
# - Olive, Wes and the rest have no punches at meetings.
#
# Punches carry the note "Sample attendance" and are replaced on each run, so
# reloading moves them with the meetings.
Hbr::SampleData.feature "feature/checklists-attendance" do |s|
  checklist = Checklist.find_by(title: "Trip Eligibility")
  next s.note("no Trip Eligibility checklist (load feature/checklists first)") unless checklist

  admin = s.login(:admin)
  youth = s.team(:youth)
  season_start, season_end = s.clock.season
  period = s.upsert!(TimeClockPeriod, { name: "Youth Program Meetings" },
    team: youth, start_time: season_start, end_time: season_end, permission: "added_by_admin")
  meeting_type = EventType.find_or_create_by!(name: "Meeting")

  meetings = (1..6).map do |number|
    starts = s.clock.days_ago(32 - (5 * number), hour: 18)
    s.upsert!(Event, { name: "Youth Meeting #{number}" },
      event_type: meeting_type, team: youth, time_clock_period: period, location: "Community Hall",
      start_time: starts, end_time: starts + 2.hours)
  end

  TimeClockPunch.where(note: "Sample attendance").delete_all
  punch = lambda do |first, start_time, end_time|
    TimeClockPunch.create!(person: s.person(first), time_clock_period: period, start_time: start_time, end_time: end_time,
      note: "Sample attendance", created_by: admin)
  end
  meetings.each { |meeting| punch.call("Chloe", meeting.start_time, meeting.end_time) }
  [ 0, 2, 4 ].each { |index| punch.call("Grace", meetings[index].start_time, meetings[index].end_time) }
  punch.call("Kate", meetings[1].start_time, meetings[1].start_time + 45.minutes)
  punch.call("Sam", meetings[3].start_time - 4.hours, meetings[3].start_time - 1.hour)

  item = ChecklistItem.find_or_initialize_by(checklist: checklist, label: "Attendance")
  item.assign_attributes(kind: "attendance", position: 6)
  item.config_params = {
    leeway_minutes: "1", period_ids: [ period.id ],
    rules: [
      { name: "Autumn", starts: { mode: "date", date: season_start.iso8601 }, ends_on: s.clock.date(-15).iso8601, share: "20", with: "Winter" },
      { name: "Winter", starts: { mode: "date", date: s.clock.date(-14).iso8601 }, share: "40" }
    ]
  }
  item.save! if item.new_record? || item.changed?

  unless ChecklistExcuse.where(item: item, person: s.person("Grace")).where.not(event_id: nil).exists?
    ChecklistExcuse.create!(item: item, person: s.person("Grace"), event: meetings[5], reason: "Family trip, told us ahead",
      created_by: admin)
  end

  Checklists::Refresher.new(checklist.reload, silent: true).call
  status = ->(first) { checklist.checklist_results.find_by(person: s.person(first), item: item)&.status }
  s.report "Trip Eligibility attendance: #{%w[Chloe Grace Kate Sam].map { |first| "#{first} #{status.call(first)}" }.join(", ")}"
  s.expect("Chloe meets attendance") { status.call("Chloe") == "met" }
  s.expect("Kate is below the minimum") { status.call("Kate") == "not_met" }
end
