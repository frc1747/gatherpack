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
#
# "Almost" needs a count item (feature/checklists-count), so it's left to
# that layer. Carol (Youth Program) holds the Checklist Organizer badge named in
# the setting and runs the checklist.
Hbr::SampleData.people "Nina Hart"

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
    met_word: "Eligible", pending_word: "Pending", not_met_word: "Not eligible", created_by: admin,
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
end
