# Two commitments for the season. "Crew Shifts" is owed by each Facilities
# Crew member alone: 2 shifts, one per check-in at a Crew Shift event, with
# the New Volunteer badge exempting Uma. Ella has met it, Isla has one shift
# and one planned, Mia one and nothing planned, Quinn nothing, and Yara met it
# with an adjustment. "Youth Family Shifts" is owed by Youth Program families,
# grouped by the Parent relationship (from the person fields data): 2 shifts
# for the first member and 1 for each other, where 3 Setup Hour check-ins
# make 1 shift. Grace and Kate (Paula's) owe 3 together and are partway,
# Olive has met it, and the rest have nothing planned. Dan holds the
# Commitment Organizer badge named in the Commitment Organizers setting.
Hbr::SampleData.feature "feature/commitments" do |s|
  s.enable_feature :commitments
  admin = s.login(:admin)
  root = s.team(:root)
  season_start, season_end = s.clock.season
  # The season ends June 30, so late in June it ends before the events dated
  # ahead here and in the sign-ups data (up to 17 days out). Run the
  # commitments at least a month past today so those still count.
  ends_on = [ season_end, s.clock.date(30) ].max

  # Anyone with the Commitment Organizer badge (Dan) can run commitments for
  # any team.
  organizer_badge = s.upsert!(Badge, { name: "Commitment Organizer" },
    badge_type: BadgeType.find_or_create_by!(name: "Award"), team: nil, permission: "added_by_admin", color: "#613583", short: "list-check")
  BadgeAssignment.find_or_create_by!(badge: organizer_badge, person: s.person("Dan"))
  s.setting :commitments_organizers, "Commitment Organizer > #{root.name}"
  # Holders don't owe Crew Shifts this season.
  exempt_badge = s.upsert!(Badge, { name: "New Volunteer" },
    badge_type: BadgeType.find_or_create_by!(name: "Award"), team: nil, permission: "added_by_admin", color: "#2ec27e", short: "seedling")
  BadgeAssignment.find_or_create_by!(badge: exempt_badge, person: s.person("Uma"))

  # Events named in order, each `days` from today (negative for the past).
  events = lambda do |type, team, names_and_days|
    names_and_days.map do |name, days|
      start_time = s.clock.days_from_now(days, hour: 18)
      s.upsert!(Event, { name: name }, event_type: type, team: team, location: "Community Hall", start_time: start_time, end_time: start_time + 2.hours)
    end
  end
  check_in = ->(event, first) { Checkin.find_or_create_by!(event: event, person: s.person(first)) }
  commitment = lambda do |title, attrs|
    record = s.upsert!(Commitment, { title: title },
      { team: root, unit: "shifts", starts_on: season_start, ends_on: ends_on, counts_when: :confirmed, created_by: admin }.merge(attrs))
    CommitmentOrganizer.find_or_create_by!(commitment: record, person: s.person("Dan"))
    record
  end
  source = lambda do |record, type, per|
    s.upsert!(CommitmentSource, { commitment: record, kind: "checkins", subject: type }, per: per, credits: 1)
  end
  adjust = lambda do |record, first, credits, reason|
    CommitmentAdjustment.find_or_create_by!(commitment: record, person: s.person(first), reason: reason) do |adjustment|
      adjustment.credits = credits
      adjustment.created_by = admin
    end
  end

  shift_type = EventType.find_or_create_by!(name: "Crew Shift")
  cleanup, shed, gutters, fence = events.call(shift_type, s.team(:facilities),
    [ [ "Crew Shift: Grounds Cleanup", -21 ], [ "Crew Shift: Tool Shed Sort", -14 ], [ "Crew Shift: Gutter Day", -7 ], [ "Crew Shift: Paint the Fence", 7 ] ])
  crew_shifts = commitment.call("Crew Shifts",
    description: "Every Facilities Crew member works two crew shifts this season. Check in at the shift to count it.",
    owing_team: s.team(:facilities), base_amount: 2, additional_amount: 0, exempt_badge: exempt_badge, group_relationship_type: nil)
  source.call(crew_shifts, shift_type, 1)
  check_in.call(cleanup, "Ella")
  check_in.call(gutters, "Ella")
  check_in.call(shed, "Isla")
  check_in.call(fence, "Isla")
  check_in.call(cleanup, "Mia")
  check_in.call(shed, "Yara")
  check_in.call(shed, "Uma")
  adjust.call(crew_shifts, "Yara", 1, "Covered the front desk at the open house")

  setup_type = EventType.find_or_create_by!(name: "Setup Hour")
  setup = events.call(setup_type, s.team(:youth),
    [ [ "Setup Hour: Chairs", -24 ], [ "Setup Hour: Stage", -20 ], [ "Setup Hour: Signs", -16 ], [ "Setup Hour: Tables", -12 ],
      [ "Setup Hour: Lights", -8 ], [ "Setup Hour: Banners", -4 ], [ "Setup Hour: Kitchen", 4 ], [ "Setup Hour: Storage", 11 ] ])
  parent_type = RelationshipType.find_by!(parent_label: "Parent", child_label: "Child")
  family_shifts = commitment.call("Youth Family Shifts",
    description: "Each Youth Program family works two shifts this season, plus one for each additional child. Three setup hours make one shift.",
    owing_team: s.team(:youth), base_amount: 2, additional_amount: 1, exempt_badge: nil, group_relationship_type: parent_type)
  source.call(family_shifts, setup_type, 3)
  s.remember :family_shifts, family_shifts
  setup.first(6).each { |event| check_in.call(event, "Olive") }
  setup.first(3).each { |event| check_in.call(event, "Grace") }
  setup[3, 2].each { |event| check_in.call(event, "Kate") }
  check_in.call(setup[6], "Kate")

  crew = crew_shifts.reload.progress
  family = family_shifts.reload.progress
  at = ->(progress, first) { progress[s.person(first).id] }
  s.report "Crew Shifts (each Facilities Crew member) and Youth Family Shifts (grouped by family), organizer badge held by Dan"
  s.expect("Ella has met Crew Shifts") { at.(crew, "Ella").met? }
  s.expect("Isla has one shift and one planned") { at.(crew, "Isla").then { |p| p.confirmed == 1 && p.planned == 1 } }
  s.expect("Mia has one shift and nothing planned") { at.(crew, "Mia").then { |p| p.confirmed == 1 && p.planned.zero? && !p.met? } }
  s.expect("Quinn has nothing planned") { at.(crew, "Quinn").nothing_planned? }
  s.expect("Uma is exempt") { !crew_shifts.covers?(s.person("Uma")) }
  s.expect("Yara has met it with an adjustment") { at.(crew, "Yara").then { |p| p.met? && p.adjustment_credits == 1 } }
  s.expect("Grace and Kate owe 3 shifts together") { at.(family, "Grace").then { |p| p.members.size == 2 && p.owed == 3 && !p.met? } }
  s.expect("their 5 setup hours make 1 shift and 2 of 3 toward the next") do
    at.(family, "Kate").lines.find { |line| line.source.subject == setup_type }.then { |l| l.confirmed_credits == 1 && l.partial == 2 && l.planned_credits == 1 }
  end
  s.expect("Olive has met it") { at.(family, "Olive").met? }
  s.expect("Carol has nothing planned") { at.(family, "Carol").nothing_planned? }
end
