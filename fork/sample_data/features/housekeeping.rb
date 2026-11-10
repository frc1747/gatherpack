# Old things to tidy, one of each situation the bar and the purges show:
#
# - Events: "Autumn Workday" ended about 14 months ago (find it with "Ended
#   more than 12 months ago" and archive it); "Winter Workday" is already
#   archived (Restore it under "Archived ones"). "Old social" has a start
#   time only, so it counts as ended when it started.
# - Announcements: "Hall closed for repairs" ended 13 months ago.
# - Checklists: "Trip Eligibility (last year)" ended last season and
#   "Trip Packing (last year)" requires it, so archiving the first alone
#   skips it ("still used by Trip Packing (last year)"); archive both, or copy
#   them forward a year together as drafts (the new packing list requires
#   the new eligibility one, and last year's pair can then be archived).
# - Membership: Hugo Lane's application to Youth Applicants was denied 14
#   months ago, so admins see "Clear denied applications older than 12
#   months" on that team's applications.
# - Field answers: Hugo joined four years ago and has done nothing since, so
#   his Medical Notes answer shows under "Clear medical and emergency answers"
#   (the setting names the Health group) on the people list.
# - Moving people: an "Alumni" team under Northwind Community; Hugo is a
#   member of Youth Program with no activity, ready to "Move people to
#   another team".
Hbr::SampleData.people "Hugo Lane"

Hbr::SampleData.feature "feature/housekeeping" do |s|
  s.enable_feature :housekeeping
  admin = s.login(:admin)
  root = s.team(:root)
  youth = s.team(:youth)
  workday_type = EventType.find_or_create_by!(name: "Workday")

  s.upsert!(Event, { name: "Autumn Workday" },
    event_type: workday_type, team: root, location: "Community Hall", archived_at: nil,
    start_time: s.clock.days_ago(425, hour: 9), end_time: s.clock.days_ago(425, hour: 15))
  s.upsert!(Event, { name: "Winter Workday" },
    event_type: workday_type, team: root, location: "Community Hall", archived_at: s.clock.days_ago(300),
    start_time: s.clock.days_ago(330, hour: 9), end_time: s.clock.days_ago(330, hour: 15))
  s.upsert!(Event, { name: "Old social" },
    event_type: workday_type, team: root, location: "Community Hall", archived_at: nil,
    start_time: s.clock.days_ago(500, hour: 18), end_time: nil)
  s.upsert!(Announcement, { title: "Hall closed for repairs" },
    team: root, content: "The hall is closed this week while the roof is fixed.", archived_at: nil,
    start_time: s.clock.days_ago(400), end_time: s.clock.days_ago(395))

  last_start = s.clock.date(-540)
  last_end = s.clock.date(-200)
  eligibility = s.upsert!(Checklist, { title: "Trip Eligibility (last year)" },
    team: youth, status: :active, starts_on: last_start, ends_on: last_end, created_by: admin,
    description: "Last season's trip checklist.")
  packing = s.upsert!(Checklist, { title: "Trip Packing (last year)" },
    team: youth, status: :active, starts_on: last_start, ends_on: last_end, created_by: admin,
    description: "Needs the eligibility checklist done first.")
  ChecklistRule.find_or_create_by!(checklist: eligibility, item: nil, effect: :include, target_type: :team, team: youth)
  ChecklistRule.find_or_create_by!(checklist: packing, item: nil, effect: :include, target_type: :team, team: youth)
  requires = ChecklistItem.find_or_initialize_by(checklist: packing, label: "Eligible for the trip")
  requires.assign_attributes(kind: "checklist", position: 0)
  requires.config_params = { "checklist_id" => eligibility.id }
  requires.save! if requires.new_record? || requires.changed?

  alumni = Team.find_or_create_by!(name: "Alumni") do |team|
    team.team_type = root.team_type
    team.parent = root
  end
  hugo = s.person!("Hugo", "Lane")
  hugo.update_columns(created_at: s.clock.days_ago(4 * 365))
  s.member!(hugo, youth)
  hugo.memberships.where(team: youth).update_all(created_at: s.clock.days_ago(4 * 365))

  applicants = Team.find_by(name: "Youth Applicants") || Team.find_or_create_by!(name: "Youth Applicants") do |team|
    team.team_type = youth.team_type
    team.parent = youth
    team.join_permission = "requires_approval"
  end
  denied = MembershipApplication.find_or_create_by!(person: hugo, team: applicants, status: :denied)
  denied.update_columns(reviewed_at: s.clock.days_ago(425), updated_at: s.clock.days_ago(425))

  if (medical = PersonField.find_by(key: "medical_notes"))
    PersonFieldValue.find_or_create_by!(person: hugo, person_field: medical) { |value| value.value = "Asthma; inhaler in bag." }
    s.setting :housekeeping_purge_fields, medical.person_field_group&.name || medical.name
  end

  s.report "3 old events (1 archived, 1 with no end time), 1 old announcement, 2 ended checklists, 1 denied application, Alumni team"
  s.expect("Trip Packing requires Trip Eligibility") { eligibility.dependents.include?(packing) }
  s.expect("Hugo has no recent activity") { Housekeeping.people_without_activity_since(s.clock.date(-365)).include?(hugo) }
  s.expect("Hugo's denial is old enough to clear") { MembershipApplication.denied.where(id: denied.id).where(reviewed_at: ...s.clock.days_ago(365)).exists? }
  s.expect("Alumni is under Northwind Community") { alumni.parent == root }
end
