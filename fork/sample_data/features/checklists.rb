# "Trip Eligibility", a checklist on the Youth Program for the season, with
# one person in each situation the core kinds can show:
#
# - Chloe is done on everything (login, Youth Safety Training, aged 12 or
#   older, permission confirmed, First Aid or Youth Protection).
# - Grace and Kate are Paula's wards: Paula confirmed Grace's permission and
#   can confirm Kate's from Kate's Checklists tab.
# - Olive is also in Adult Education, so the safety item doesn't apply to her
#   ("Adult volunteer").
# - Wes is excused from safety training by Adam, with a reason.
# - Sam has no birthday on file, so the age item is Not yet.
# - Nina applied to Youth Applicants and is covered as an applicant only.
# - Logistics Crew members (Ben leads it) see everyone's overall and the
#   safety item through a team grant.
# - The overall reads Eligible, Pending or Not eligible (the checklist's own
#   words); items keep Complete, In Progress and Not Started.
#
# "In Progress" needs a count item (feature/checklists-connectors), so it's left to
# that layer. Carol (Youth Program) holds the Checklist Organizer badge named in
# the setting and runs the checklist.
Hbr::SampleData.people "Nina Hart"


# Adds an Attendance item to "Trip Eligibility" (below) with
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
attendance = lambda do |s|
  checklist = Checklist.find_by(title: "Trip Eligibility")
  next s.note("no Trip Eligibility checklist (the checklists data didn't load)") unless checklist

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

# Profile-field items for "Trip Eligibility" (feature/checklists, with the fields person-fields creates).
#
# Two profile-field items on the core's "Trip Eligibility" checklist, using
# the Photo Release and Emergency Contact fields person-fields creates:
#
# - "Photo release" (is yes): Chloe and Grace are done, Kate's release is
#   set to no, everyone else is blank and so Not yet.
# - "Emergency contact" (is filled in, changed since the season began):
#   Chloe's is current, Grace's was last changed before the season started
#   (Not yet, "Not changed since ..."), the rest are blank.
person_fields = lambda do |s|
  s.enable_feature :checklists
  s.enable_feature :person_fields
  checklist = Checklist.find_by!(title: "Trip Eligibility")
  season_start, = s.clock.season
  photo = PersonField.find_by!(key: "photo_release")
  contact = PersonField.find_by!(key: "emergency_contact")

  item = lambda do |label, position, config|
    record = ChecklistItem.find_or_initialize_by(checklist: checklist, label: label)
    record.assign_attributes(kind: "person_field", position: position)
    record.config_params = config
    record.save! if record.new_record? || record.changed?
    record
  end
  item.call("Photo release", 6, { field_id: photo.id, operator: "yes" })
  item.call("Emergency contact", 7, { field_id: contact.id, operator: "filled_in", changed_since: { mode: "date", date: season_start.iso8601 } })

  # Fills a blank field; a value another feature's sample data already set
  # (person-fields gives Grace a contact) is kept. A given date is applied
  # either way, so "changed since" sees the field as last changed then.
  fill = lambda do |first, field, value, changed_at = nil|
    person = s.person(first)
    person.set_field_value(field, value) unless PersonFieldValue.exists?(person: person, person_field: field)
    PersonFieldValue.where(person: person, person_field: field).update_all(updated_at: changed_at) if changed_at
  end
  fill.call("Chloe", photo, true)
  fill.call("Grace", photo, true)
  fill.call("Kate", photo, false)
  fill.call("Chloe", contact, "Dana Reyes, 555-0142", s.clock.days_ago(5))
  fill.call("Grace", contact, "Paula Miller, 555-0187", season_start - 30)

  Checklists::Refresher.new(checklist.reload, silent: true).call
  results = ->(label, first) { checklist.checklist_results.find_by(item: checklist.checklist_items.find_by!(label: label), person: s.person(first)) }
  s.expect("Chloe's photo release is met") { results.call("Photo release", "Chloe")&.met? }
  s.expect("Kate's photo release is not met") { results.call("Photo release", "Kate")&.not_met? }
  s.expect("Grace's emergency contact is out of date") { results.call("Emergency contact", "Grace")&.not_met? }
end

Hbr::SampleData.feature "feature/checklists" do |s|
  s.enable_feature :checklists
  admin = s.login(:admin)
  root = s.team(:root)
  youth = s.team(:youth)
  season_start, season_end = s.clock.season
  ends_on = [ season_end, s.clock.date(30) ].max
  award = BadgeType.find_or_create_by!(name: "Award")
  certification = BadgeType.find_or_create_by!(name: "Certification")

  organizer_badge = s.upsert!(Badge, { name: "Checklist Organizer" },
    badge_type: award, team: nil, permission: "added_by_admin", color: "#613583", short: "list-check")
  BadgeAssignment.find_or_create_by!(badge: organizer_badge, person: s.person("Carol"))
  s.setting :checklists_organizers, "Checklist Organizer > #{root.name}"

  safety = s.upsert!(Badge, { name: "Youth Safety Training" },
    badge_type: certification, team: nil, permission: "added_by_admin", color: "#e5a50a", short: "helmet-safety")
  %w[Chloe Grace Kate Olive Sam].each { |first| BadgeAssignment.find_or_create_by!(badge: safety, person: s.person(first)) }
  BadgeAssignment.find_or_create_by!(badge: Badge.find_by!(name: "Youth Protection"), person: s.person("Chloe"))

  s.login!(:youth_lead, "chloe", "Chloe", s.person("Chloe").last_name)
  { "Chloe" => 30, "Wes" => 15, "Carol" => 13 }.each do |first, age|
    s.person(first).update!(birthday: s.clock.date(-200) << (12 * age))
  end
  s.person("Sam").update!(birthday: nil)

  applicants = Team.find_or_create_by!(name: "Youth Applicants") do |team|
    team.team_type = youth.team_type
    team.parent = youth
    team.join_permission = "requires_approval"
  end
  nina = s.person!("Nina", "Hart")
  MembershipApplication.find_or_create_by!(person: nina, team: applicants, status: :pending)

  checklist = s.upsert!(Checklist, { title: "Trip Eligibility" },
    team: youth, status: :active, starts_on: season_start, ends_on: ends_on, read_level: "family",
    created_by: admin, met_word: "Eligible", pending_word: "Pending", not_met_word: "Not eligible",
    description: "Everything someone needs before the spring trip.")
  ChecklistOrganizer.find_or_create_by!(checklist: checklist, person: s.person("Carol"))
  rule = ->(attrs) { ChecklistRule.find_or_create_by!({ checklist: checklist }.merge(attrs)) }
  rule.call(item: nil, effect: :include, target_type: :team, team: youth)
  rule.call(item: nil, effect: :include, target_type: :applicants, team: applicants)

  item = lambda do |label, kind, position, config = {}, **attrs|
    record = ChecklistItem.find_or_initialize_by(checklist: checklist, label: label)
    record.assign_attributes({ kind: kind, position: position }.merge(attrs))
    record.config_params = config
    record.save! if record.new_record? || record.changed?
    record
  end
  item.call("Login", "has_login", 1)
  safety_item = item.call("Safety training", "badge", 2, { badge_ids: [ safety.id ] }, exempt_label: "Adult volunteer")
  rule.call(item: safety_item, effect: :exclude, target_type: :team, team: s.team(:adult))
  item.call("Age", "age", 3, { min: 12 })
  permission = item.call("Trip permission", "attested", 4, { statement: "Trip permission given", attested_by: "guardian" })
  either = item.call("First aid or youth protection", "any_of", 5)
  item.call("First Aid", "badge", 1, { badge_ids: [ Badge.find_by!(name: "First Aid").id ] }, parent: either)
  item.call("Youth Protection", "badge", 2, { badge_ids: [ Badge.find_by!(name: "Youth Protection").id ] }, parent: either)

  { "Chloe" => s.person("Chloe"), "Grace" => s.login(:parent1) }.each do |first, by|
    next if ChecklistAttestation.exists?(person: s.person(first), key: permission.config["key"])

    ChecklistAttestation.create!(person: s.person(first), key: permission.config["key"], statement: permission.config["statement"],
      attested_by: by, attested_as: "guardian", attested_at: s.clock.days_ago(3))
  end
  unless ChecklistExcuse.exists?(item: safety_item, person: s.person("Wes"))
    ChecklistExcuse.create!(item: safety_item, person: s.person("Wes"), reason: "Training booked for next month", created_by: admin)
  end
  ChecklistGrant.find_or_create_by!(checklist: checklist, team: s.team(:logistics)) do |grant|
    grant.item_ids = [ safety_item.id ]
    grant.access = :status
  end

  Checklists::Refresher.new(checklist.reload, silent: true).call
  counts = checklist.checklist_results.where(item_id: nil).group(:status).count
  s.report "Trip Eligibility: #{counts.map { |status, count| "#{count} #{checklist.word_for(status).downcase}" }.join(", ")}"
  s.expect("Chloe is eligible") { checklist.checklist_results.find_by(person: s.person("Chloe"), item_id: nil)&.met? }

  attendance.call(s)
  person_fields.call(s)
end
