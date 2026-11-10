# Connector data for "Trip Eligibility" (feature/checklists), in four parts that run in this order:
# count, forms, sign-up sheets, and the time kiosk's "what's left" box.
# Each part keeps its own explanation below.
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
count = lambda do |s|
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

# Adds two form items to "Trip Eligibility" (feature/checklists) and a form
# that asks the people the checklist covers:
#
# - "Parent consent" reads Parent Consent (feature/forms): Grace is done,
#   Kate is almost (waiting for Paula's signature), Olive is not yet (needs
#   confirming again after a profile change). Nina, an applicant on no team,
#   isn't asked by that form, so she is not yet and the checklist lists it
#   as a problem. Chloe has no guardian linked; an admin excused her (paper
#   consent on file), so she stays eligible for the trip seat sign-ups use.
# - "Trip medical release" reads Trip Medical Release, signed within the
#   last 12 months. Its audience is "everyone Trip Eligibility covers", so
#   Nina is asked too. Chloe has signed it; with forms expiry present it is
#   good for 12 months and shows "Good until <date>".
forms = lambda do |s|
  admin = s.login(:admin)
  checklist = Checklist.find_by!(title: "Trip Eligibility")
  consent = Form.find_by!(key: "parent_consent")

  release = s.upsert!(Form, { key: "trip_medical_release" },
    title: "Trip Medical Release", team: s.team(:youth), created_by: admin,
    respond_permission: "family", read_permission: "family",
    description: "Allergies, medicines and who to call, for everyone going on the spring trip.")
  release.update!(valid_for_months: 12) if release.respond_to?(:valid_for_months=)
  s.upsert!(FormQuestion, { form: release, key: "accurate" }, position: 1, kind: "acknowledgment",
    label: "The medical details on my profile are up to date.", required: true)
  FormAudienceRule.find_or_create_by!(form: release, effect: "include", target_type: "checklist", checklist: checklist, checklist_match: "covered")
  release.update!(status: "open") unless release.open?

  chloe = s.person("Chloe")
  response = release.form_responses.find_or_create_by!(subject: chloe)
  unless response.active_submission
    access = FormAccess.new(chloe, chloe, release)
    submission = response.start_submission!(chloe)
    submission.assign_answers({ "accurate" => "1" }, access)
    submission.save!
    errors = submission.submit!(chloe, access)
    raise Hbr::SampleData::Error, "Trip Medical Release for Chloe: #{errors}" if errors.any?
  end

  item = lambda do |label, position, config, **attrs|
    record = ChecklistItem.find_or_initialize_by(checklist: checklist, label: label)
    record.assign_attributes({ kind: "form_complete", position: position }.merge(attrs))
    record.config_params = config
    record.save! if record.new_record? || record.changed?
    record
  end
  consent_item = item.call("Parent consent", 6, { form_ids: [ consent.id ] })
  release_item = item.call("Trip medical release", 7, { form_ids: [ release.id ] }, starts_within_amount: 12, starts_within_unit: "months")

  unless ChecklistExcuse.exists?(item: consent_item, person: chloe)
    ChecklistExcuse.create!(item: consent_item, person: chloe, reason: "Paper consent on file", created_by: admin)
  end

  Checklists::Refresher.new(checklist.reload, silent: true).call
  status = ->(record, first) { checklist.checklist_results.find_by(item: record, person: s.person(first))&.status }
  s.report "Trip Eligibility: Parent consent and Trip medical release items"
  s.expect("Grace's consent is done") { status.call(consent_item, "Grace") == "met" }
  s.expect("Kate's consent is almost, waiting for Paula") { status.call(consent_item, "Kate") == "pending" }
  s.expect("Nina isn't asked Parent Consent, and it's a problem") do
    status.call(consent_item, "Nina") == "not_met" && checklist.problems.any? { |problem| problem.include?("aren't asked Parent Consent") || problem.include?("isn't asked Parent Consent") }
  end
  s.expect("Nina is asked Trip Medical Release through the checklist") { release.reload.in_audience?(s.person("Nina")) }
  s.expect("Chloe is excused from Parent consent") { status.call(consent_item, "Chloe") == "exempt" }
  s.expect("Chloe's medical release is done") { status.call(release_item, "Chloe") == "met" }
end

# "Spring Trip Seats", a Youth Program sign-up sheet for the spring trip,
# whose Trip seat position needs "Trip Eligibility" (from the checklists
# data) done. Chloe, eligible, can take a seat and has one; Sam, with no
# birthday on file, sees "Needs Trip Eligibility: Eligible" on the slot and,
# above the dates, the checklist with what's left (Age: add a birthday).
# The Helper position has no rule, so anyone on the sheet can take it.
signups = lambda do |s|
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

# Builds on the "Trip Eligibility" checklist (feature/checklists sample data,
# with its "Photo release" item). That item is
# marked to list at the time kiosk while it isn't done. Scan Kate's card (her
# photo release is set to no): a "You still need" box lists "Photo release".
# Chloe's release is yes, so her card shows nothing extra. Managers' cards
# never show the box. Each uses her scan card, or gets one outside the base
# range (10000001-10000032) if she has none.
kiosk = lambda do |s|
  s.enable_feature :checklists
  checklist = Checklist.find_by!(title: "Trip Eligibility")
  photo = checklist.checklist_items.find_by!(label: "Photo release")
  photo.update!(show_on_kiosk: true) unless photo.show_on_kiosk?

  Checklists::Refresher.new(checklist.reload, silent: true).call
  kate = s.person("Kate")
  chloe = s.person("Chloe")
  cards = { kate => "10000111", chloe => "10000112" }.to_h do |person, value|
    [ person, Token.find_by(tokenable: person) || Token.find_or_create_by!(value: value) { |token| token.tokenable = person } ]
  end
  s.report "Photo release lists at the time kiosk while not done: scan card #{cards[kate].value} (Kate; lists it), #{cards[chloe].value} (Chloe; done)"
  s.expect("the photo release item is marked for the kiosk") { photo.reload.show_on_kiosk? }
  s.expect("Kate's card lists the photo release") { Checklists::KioskLines.for(kate).include?("Photo release") }
  s.expect("Chloe's card doesn't list it") { Checklists::KioskLines.for(chloe).exclude?("Photo release") }
end

Hbr::SampleData.feature "feature/checklists-connectors" do |s|
  count.call(s)
  forms.call(s)
  signups.call(s)
  kiosk.call(s)
end
