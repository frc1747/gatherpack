# A calendar note linked to a team, so the Calendar Notes list shows the
# team's badge beside it (it raised an error before this fix).
Hbr::SampleData.feature "feature/calendar-note-badge" do |s|
  facilities = s.team(:facilities)

  s.upsert!(CalendarNote, { name: "Shop closed for cleaning" },
    description: "Facilities Crew deep-cleans the shop.", noteable: facilities,
    start_time: s.clock.days_from_now(10), end_time: s.clock.days_from_now(10) + 3.hours)

  s.report "Calendar note \"Shop closed for cleaning\" linked to Facilities Crew"
end
