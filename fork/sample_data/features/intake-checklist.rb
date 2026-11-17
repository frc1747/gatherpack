# "Joining Northwind": the checklist the "Join Northwind" registration
# (feature/intake sample data) points to. It covers applicants to Junior
# Crew and Volunteer Pool and the members of Junior Crew, so one list shows
# both people joining and people coming back. Items: a login, and a family
# agreement a guardian (or the person) confirms. Rosa has confirmed hers, so her application
# shows "2 of 2 done"; Leo, Theo and Milo show "1 of 2 done" and what's
# missing; Ivy, already in Junior Crew, is on the report as not done (who
# hasn't come back). Approval doesn't wait for the checklist: tick "Approve
# only when the checklist is done" on the registration to try the gate, then
# approve Leo and Rosa together from Junior Crew's applications page.
# Hana signs in and confirms the agreement for Milo from /join/<slug>/me.
# Form items with a date (signed long ago, due again) come with
# feature/checklists-connectors.
Hbr::SampleData.people([])

Hbr::SampleData.feature "feature/intake-checklist" do |s|
  s.enable_feature :checklists
  admin = s.login(:admin)
  root = s.team(:root)
  junior_crew = s.team(:junior_crew)
  volunteer_pool = s.team(:volunteer_pool)
  registration = Intake::Registration.find_by!(title: "Join Northwind")

  checklist = s.upsert!(Checklist, { title: "Joining Northwind" },
    team: root, status: :active, starts_on: s.clock.days_ago(30).to_date, ends_on: s.clock.days_from_now(300).to_date,
    read_level: "family", created_by: admin, description: "What everyone joining or coming back needs to do.")
  rule = ->(attrs) { ChecklistRule.find_or_create_by!({ checklist: checklist, item: nil, effect: :include }.merge(attrs)) }
  rule.call(target_type: :applicants, team: junior_crew)
  rule.call(target_type: :applicants, team: volunteer_pool)
  rule.call(target_type: :team, team: junior_crew)

  item = lambda do |label, kind, position, config = {}, **attrs|
    record = ChecklistItem.find_or_initialize_by(checklist: checklist, label: label)
    record.assign_attributes({ kind: kind, position: position }.merge(attrs))
    record.config_params = config
    record.save! if record.new_record? || record.changed?
    record
  end
  item.call("Login", "has_login", 1)
  agreement = item.call("Family agreement", "attested", 2, { statement: "Family agreement read", attested_by: "guardian" })

  registration.update!(checklist: checklist) unless registration.checklist_id == checklist.id

  rosa = Person.joins(:user).find_by!(first_name: "Rosa", last_name: "Vale")
  unless ChecklistAttestation.exists?(person: rosa, key: agreement.config["key"])
    ChecklistAttestation.create!(person: rosa, key: agreement.config["key"], statement: agreement.config["statement"],
      attested_by: rosa, attested_as: "person", attested_at: s.clock.days_ago(1))
  end

  Checklists::Refresher.new(checklist.reload, silent: true).call
  done = ->(person) { checklist.checklist_results.find_by(person: person, item_id: nil)&.met? }
  s.report "Joining Northwind on Join Northwind: Rosa done; Leo, Theo and Milo not yet; Ivy (returning) not yet"
  s.expect("Rosa's checklist is done") { done.call(rosa) }
  s.expect("Leo's checklist isn't") { !done.call(Person.find_by!(first_name: "Leo", last_name: "Hart")) }
  s.expect("Ivy, already a member, is covered") { checklist.checklist_results.exists?(person: Person.find_by!(first_name: "Ivy", last_name: "Reyes"), item_id: nil) }
end
