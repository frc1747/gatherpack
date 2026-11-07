# "Spring Trip Seats", a Youth Program sign-up sheet for the spring trip,
# whose Trip seat position needs "Trip Eligibility" (from the checklists
# data) done. Chloe, eligible, can take a seat and has one; Sam, with no
# birthday on file, sees "Needs Trip Eligibility: Eligible" on the slot and,
# above the dates, the checklist with what's left (Age: add a birthday).
# The Helper position has no rule, so anyone on the sheet can take it.
Hbr::SampleData.feature "feature/checklists-signups" do |s|
  admin = s.login(:admin)
  youth = s.team(:youth)
  checklist = Checklist.find_by!(title: "Trip Eligibility")

  workday_type = EventType.find_or_create_by!(name: "Workday")
  trip = s.upsert!(Event, { name: "Spring Trip" }, event_type: workday_type, team: youth, location: "Lakeside Camp",
    start_time: s.clock.days_from_now(24, hour: 8), end_time: s.clock.days_from_now(24, hour: 18))
  sheet = s.upsert!(SignupSheet, { title: "Spring Trip Seats" }, team: youth, status: :open, created_by: admin,
    description: "Take a seat on the bus. Seats need Trip Eligibility done; the sheet says what's left.",
    contact: "Carol, carol@example.com")
  SignupSheetEvent.find_or_create_by!(signup_sheet: sheet, event: trip)
  seat = s.upsert!(SignupPosition, { signup_sheet: sheet, name: "Trip seat" }, position: 0, kind: :people, capacity: 20)
  s.upsert!(SignupPosition, { signup_sheet: sheet, name: "Helper" }, position: 1, kind: :people, capacity: 4,
    description: "Load the bus and hand out lunches")
  s.upsert!(SignupPositionRule, { signup_position: seat, kind: "checklist" }, checklist: checklist, accept_pending: false)
  sheet.sync_slots!

  Checklists::Refresher.new(checklist.reload, silent: true).call
  slot = seat.signup_slots.find_by!(event: trip)
  chloe = s.person("Chloe")
  Signup.find_by(signup_slot: slot, person: chloe) || Signup.place!(slot: slot, person: chloe, signed_up_by: chloe)

  rule = seat.signup_position_rules.find_by!(kind: "checklist")
  s.report "Spring Trip Seats: #{rule.description}"
  s.expect("Chloe has a trip seat") { Signup.live.exists?(signup_slot: slot, person: chloe) }
  s.expect("Sam can't take a seat yet") { rule.reload.check(s.person("Sam"), trip) == "Needs Trip Eligibility: Eligible" }
end
