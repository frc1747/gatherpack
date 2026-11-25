# A "Community Outreach" event type whose new events start locked, and one
# upcoming event of that type, created after the type was marked, so it starts
# locked: member@ can't check themselves in, the Youth Program's manager can.
Hbr::SampleData.feature "feature/event-type-starts-locked" do |s|
  s.enable_feature :event_type_starts_locked
  outreach = EventType.find_or_create_by!(name: "Community Outreach")
  outreach.update!(starts_locked: true)

  fair = Event.find_or_initialize_by(name: "Library Open House")
  fair.update!(event_type: outreach, team: s.team(:youth), location: "Public library",
    start_time: s.clock.days_from_now(9, hour: 10), end_time: s.clock.days_from_now(9, hour: 13))

  s.report "\"Community Outreach\" events start locked; \"Library Open House\" is locked"
  s.expect("Library Open House is locked") { fair.reload.locked? }
end
