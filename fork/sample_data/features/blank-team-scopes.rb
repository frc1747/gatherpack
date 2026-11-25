# An event with no team: every signed-in member sees it on the Events list and
# the calendar, not just admins. Sign in as a member to check.
Hbr::SampleData.feature "feature/blank-team-scopes" do |s|
  type = EventType.find_or_create_by!(name: "Workday")
  s.upsert!(Event, { name: "Open House" },
    event_type: type, team: nil, location: "Community Hall",
    start_time: s.clock.days_from_now(12, hour: 18), end_time: s.clock.days_from_now(12, hour: 20))
end
