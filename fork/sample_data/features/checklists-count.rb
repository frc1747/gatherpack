# The two commitments from the commitments data, Crew Shifts and Youth Family
# Shifts, are wrapped as one-item checklists, as the migration does on a
# real upgrade; who owes, progress and organizers stay as they were. Isla has
# one Crew Shift and one planned, so her count shows Almost.
#
# Trip Eligibility gains a pooled count item, "Car wash shift": one shift per
# family, through the Parent relationship, from check-ins at Car Wash events.
# Chloe worked last week's wash, so she stays eligible. Grace has signed up
# for the next one (a check-in at an event not yet held), so she and Kate
# share one Almost; the rest are Not yet.
Hbr::SampleData.feature "feature/checklists-count" do |s|
  s.enable_feature :checklists
  youth = s.team(:youth)

  Checklists::WrapCommitments.new.up
  crew = Checklist.find_by!(title: "Crew Shifts")

  wash_type = EventType.find_or_create_by!(name: "Car Wash")
  wash = lambda do |name, days|
    start_time = s.clock.days_from_now(days, hour: 10)
    s.upsert!(Event, { name: name }, event_type: wash_type, team: youth, location: "Community Hall parking lot",
      start_time: start_time, end_time: start_time + 3.hours)
  end
  last_wash = wash.call("Car Wash: Spring Kickoff", -7)
  next_wash = wash.call("Car Wash: Trip Fund", 9)
  Checkin.find_or_create_by!(event: last_wash, person: s.person("Chloe"))
  Checkin.find_or_create_by!(event: next_wash, person: s.person("Grace"))

  checklist = Checklist.find_by!(title: "Trip Eligibility")
  parent_type = RelationshipType.find_by!(parent_label: "Parent", child_label: "Child")
  item = ChecklistItem.find_or_initialize_by(checklist: checklist, label: "Car wash shift")
  item.assign_attributes(kind: "count", position: 6)
  item.config_params = { base_amount: 1, unit: "shifts", additional_amount: 0, group_relationship_type_id: parent_type.id, counts_when: "confirmed" }
  item.save! if item.new_record? || item.changed?
  s.upsert!(CommitmentSource, { commitment: item.commitment, kind: "checkins", subject: wash_type }, per: 1, credits: 1)

  [ crew, checklist ].each { |list| Checklists::Refresher.new(list.reload, silent: true).call }
  status = ->(list, first, record = nil) { list.checklist_results.find_by(person: s.person(first), item: record)&.status }
  s.report "Crew Shifts and Youth Family Shifts wrapped as checklists; Trip Eligibility has a pooled car wash count"
  s.expect("both commitments are wrapped") { Commitment.where(title: [ "Crew Shifts", "Youth Family Shifts" ]).all?(&:checklist_item) }
  s.expect("Isla's Crew Shifts count is almost done") { status.(crew, "Isla", crew.checklist_items.sole) == "pending" }
  s.expect("Chloe is still eligible") { status.(checklist, "Chloe") == "met" }
  s.expect("Grace and Kate share one almost-done car wash shift") { status.(checklist, "Grace", item) == "pending" && status.(checklist, "Kate", item) == "pending" }
end
