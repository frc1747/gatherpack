# "Join Northwind": an open registration run by Northwind Community, with
# the link and the kiosk on. People may apply to Junior Crew or Volunteer
# Pool (both need approval); approval also adds them to Programs and gives
# "Joined Online"; the approver picks Crew A or Crew B; guardians join
# Families. Its states: an unfinished self-service sign-up (Nina), an
# expired one (Ned, deleted by the next expiry job run), a kiosk sign-up
# waiting to finish for 4 days with no guardian confirmed yet (Theo), an
# application waiting for a guardian (Leo), one that might be someone
# already on file (Rosa, and a Rosa Vale with no login), one denied with a
# reason (Max), and a returning family (Hana, whose daughter Ivy is already
# in Junior Crew, applying for Ivy's brother Milo). Everything goes through
# the models the app uses. Checklist states (fully met, due again, turning
# 18) come with feature/intake-checklist.
Hbr::SampleData.people([ "Theo Park", "Leo Hart", "Rosa Vale", "Max Ward", "Hana Reyes", "Ivy Reyes", "Milo Reyes" ])

Hbr::SampleData.feature "feature/intake" do |s|
  s.enable_feature :intake
  root = s.team(:root)
  programs = s.team(:programs)
  crew_type = TeamType.find_or_create_by!(name: "Crew") { |t| t.icon = "people-group" }

  team = lambda do |key, name, color, join_permission|
    record = s.team!(key, name, crew_type, color, programs)
    record.update!(join_permission: join_permission) unless record.join_permission == join_permission.to_s
    record
  end
  junior_crew = team.call(:junior_crew, "Junior Crew", "#3584e4", :requires_approval)
  volunteer_pool = team.call(:volunteer_pool, "Volunteer Pool", "#9141ac", :requires_approval)
  crew_a = team.call(:crew_a, "Crew A", "#26a269", :added_by_manager)
  crew_b = team.call(:crew_b, "Crew B", "#2ec27e", :added_by_manager)
  families = team.call(:families, "Families", "#e66100", :added_by_manager)

  parent_type = s.upsert!(RelationshipType, { parent_label: "Parent", child_label: "Child" }, permission: "added_by_manager", guardianship: "minor")
  joined = s.upsert!(Badge, { name: "Joined Online" },
    badge_type: BadgeType.find_or_create_by!(name: "Award"), team: nil, permission: "added_by_admin", color: "#1c71d8", short: "door-open")

  registration = Intake::Registration.find_or_initialize_by(title: "Join Northwind")
  registration.assign_attributes(team: root, opens_at: s.clock.days_ago(14), closes_at: s.clock.days_from_now(30, hour: 23),
    self_service: true, kiosk: true, guardian_relationship_type: parent_type, created_by: s.login(:admin),
    apply_team_ids: [ junior_crew.id, volunteer_pool.id ], also_add_team_ids: [ programs.id ],
    pick_one_team_ids: [ crew_a.id, crew_b.id ], guardian_also_add_team_ids: [ families.id ], badge_ids: [ joined.id ])
  registration.save!
  s.report "registration Join Northwind (/join/#{registration.slug}, kiosk at /join/#{registration.slug}/kiosk)"

  entry_for = lambda do |first, last, source: :link, person: nil, verified: true, teams: [ junior_crew ]|
    registration.entries.find_by(first_name: first, last_name: last) ||
      registration.entries.create!(first_name: first, last_name: last, source: source, person: person,
        email: "#{first}.#{last}@example.com".downcase, verified_at: verified ? s.clock.days_ago(2) : nil,
        facts: { "team_ids" => teams.map(&:id) })
  end
  # A person with a login (found by the login, so a same-named person
  # without one stays separate).
  login = lambda do |first, last, birthday: nil|
    user = User.find_or_initialize_by(email: "#{first}.#{last}@example.com".downcase)
    user.password = "password123" if user.new_record?
    user.save!
    person = user.person || Person.create!(user: user, first_name: first, last_name: last)
    person.update!(birthday: birthday) if birthday && person.birthday != birthday
    person
  end
  apply = lambda do |entry, person, teams = nil|
    enrollment = Intake::Enrollment.new(entry)
    enrollment.applicant_member!(person)
    teams ? enrollment.apply(person, teams) : enrollment.apply(person)
  end

  # Signed up through the link, email not confirmed yet: only an entry.
  entry_for.call("Nina", "Novak", verified: false, teams: [ volunteer_pool ])
  # Never confirmed, past the 7 days entries are kept.
  ned = entry_for.call("Ned", "Stone", verified: false)
  ned.update_column(:created_at, s.clock.days_ago(9))

  # At the kiosk four days ago, 13, with a guardian named who hasn't confirmed.
  theo = login.call("Theo", "Park")
  theo_entry = entry_for.call("Theo", "Park", source: :kiosk, person: theo, verified: false)
  theo_entry.update!(facts: theo_entry.facts.merge("birth_year" => (s.clock.today.year - 13).to_s, "needs_guardian" => true, "new_login" => true))
  theo_entry.update_column(:created_at, s.clock.days_ago(4))
  apply.call(theo_entry, theo)
  unless theo_entry.household_members.guardian.exists?
    Intake::Enrollment.new(theo_entry).name_guardian(ward: theo, first_name: "Pam", last_name: "Park", email: "pam.park@example.com")
  end

  # Confirmed their email, 15, no guardian yet: "Waiting for a guardian".
  leo = login.call("Leo", "Hart", birthday: s.clock.date(-30) << (12 * 15))
  apply.call(entry_for.call("Leo", "Hart", person: leo), leo)

  # Might be the Rosa Vale already on file (no login).
  Person.create!(first_name: "Rosa", last_name: "Vale") unless Person.where(first_name: "Rosa", last_name: "Vale", user_id: nil).exists?
  rosa = login.call("Rosa", "Vale", birthday: s.clock.date(-40) << (12 * 34))
  apply.call(entry_for.call("Rosa", "Vale", person: rosa, teams: [ volunteer_pool ]), rosa)

  # Denied, with the reason the applicant was sent.
  max = login.call("Max", "Ward", birthday: s.clock.date(-50) << (12 * 40))
  apply.call(entry_for.call("Max", "Ward", person: max, teams: [ volunteer_pool ]), max)
  max_application = max.membership_applications.find_by(team: volunteer_pool)
  max_application.deny!("Volunteer Pool is full for now. We'll write when there's room.") if max_application&.pending?

  # A returning family: Ivy is already in Junior Crew; Hana adds her brother.
  hana = login.call("Hana", "Reyes", birthday: s.clock.date(-60) << (12 * 42))
  ivy = s.person!("Ivy", "Reyes", birthday: s.clock.date(-70) << (12 * 15))
  s.member!(ivy, junior_crew)
  hana_entry = entry_for.call("Hana", "Reyes", person: hana)
  enrollment = Intake::Enrollment.new(hana_entry)
  enrollment.applicant_member!(hana)
  enrollment.link_guardian(guardian: hana, ward: ivy)
  unless Person.exists?(first_name: "Milo", last_name: "Reyes")
    enrollment.add_ward(adder: hana, first_name: "Milo", last_name: "Reyes", birthday: s.clock.date(-80) << (12 * 12), teams: [ junior_crew.id ])
  end
  milo = Person.find_by!(first_name: "Milo", last_name: "Reyes")

  s.report "6 sign-ups: Nina unfinished, Ned expired, Theo waiting to finish (kiosk), Leo waiting for a guardian, Rosa a possible match, Max denied"
  s.report "Hana's family: Ivy already in Junior Crew, Milo applying"
  s.expect("Leo is waiting for review in Junior Crew") { leo.membership_applications.pending.exists?(team: junior_crew, registration: registration) }
  s.expect("Theo's kiosk sign-up is waiting to finish") { theo_entry.reload.verified_at.nil? && theo.user.intake_login_verified_at.nil? }
  s.expect("Rosa is flagged as a possible match") { Intake::HouseholdMember.find_by(person: rosa)&.possible_match.present? }
  s.expect("Max was denied with a reason") { max.membership_applications.denied.where.not(reviewer_notes: nil).exists? }
  s.expect("Milo is Hana's ward and applying") { hana.wards.include?(milo) && milo.membership_applications.pending.exists?(team: junior_crew) }
  s.expect("Nina has no person or login") { !Person.exists?(first_name: "Nina", last_name: "Novak") }
end
