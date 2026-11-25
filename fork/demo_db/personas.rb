# Adds the documentation personas (Demo Member, Demo Lead, Demo Mentor, Demo
# Student, Demo Veteran, Demo Parent, Demo Admin) to an anonymized demo database. Run by bin/fork-make-demo-db after anonymize.rb.
# Everything goes through the models, as if each persona had done it.
#
# Env: DEMO_PASSWORD.
require_relative "guard"

DemoDb.guard!
PASSWORD = ENV["DEMO_PASSWORD"].presence || "password123"

PERSONAS = [
  { first: "Demo", last: "Member", email: "demo.member@example.invalid", gender: "F", shirt_size: "M", birthday: "2011-03-14",
    teams: { "Team 1747 - Class of 2029" => false },
    badges: [ "2027 Season Safety Training Complete", "2027 FIRST Registered", "2027 Season Rookie" ],
    checkins: { "Outreach" => 2 } },
  { first: "Demo", last: "Lead", email: "demo.lead@example.invalid", gender: "M", shirt_size: "L", birthday: "2009-05-02",
    teams: { "Team 1747 - Class of 2027" => false, "Team 1747 - Student Leadership" => true },
    badges: [ "2027 Season Safety Training Complete", "2027 FIRST Registered", "2027 FIRST Consent Signed", "Student Form Creator" ] },
  { first: "Demo", last: "Mentor", email: "demo.mentor@example.invalid", gender: "F", shirt_size: "L", birthday: "1983-09-21",
    teams: { "Mentors" => true, "Team 1747 - Student Leadership" => true },
    badges: [ "2027 Season TSC Mentor Requirements", "Events Coordinator", "Sign-up Organizer", "2027 Season FIRST Mentor Ready Certified" ],
    organizes: [ "Concessions Stocking" ] },
  # Behind: some meetings missed, no Outreach or Concessions, and the meal
  # choices form a checklist lists left unsubmitted (so no forms at all).
  { first: "Sam", last: "Student", email: "demo.student@example.invalid", gender: "M", shirt_size: "M", birthday: "2010-08-19",
    teams: { "Team 1747 - Class of 2028" => false },
    badges: [ "2027 Season Safety Training Complete", "2027 FIRST Registered", "2027 FIRST Consent Signed" ],
    forms: 0, signups: 0, attends: 3, item_quantities: true },
  # All done: every checklist item met, and two upcoming sign-ups.
  { first: "Demo", last: "Veteran", email: "demo.veteran@example.invalid", gender: "F", shirt_size: "S", birthday: "2009-11-30",
    teams: { "Team 1747 - Class of 2027" => false },
    badges: [ "2027 Season Safety Training Complete", "2027 FIRST Registered", "2027 FIRST Consent Signed" ],
    listed_forms: true, item_quantities: true, checkins: { "Outreach" => 2, "Concessions" => 2 }, attends: 1 },
  # Guardian of Demo Member and Sam Student, through the relationship Concessions pools on.
  { first: "Demo", last: "Parent", email: "demo.parent@example.invalid", gender: "F", shirt_size: "M", birthday: "1980-02-08",
    teams: { "Team 1747 - Parents" => false }, badges: [], forms: 0, signups: 0,
    guardian_of: %w[demo.member@example.invalid demo.student@example.invalid] },
  # Site admin for the admin guides (Settings, Setup pages, imports). Not a
  # mentor and holds no badges, so it gets no approval or to-do notices.
  { first: "Demo", last: "Admin", email: "demo.admin@example.invalid", gender: "M", shirt_size: "L", birthday: "1978-06-11",
    teams: {}, badges: [], forms: 0, signups: 0, admin: true }
].freeze

def say(label, value = nil)
  puts value.nil? ? "== #{label}" : "   #{label}: #{value}"
end

# A finished answer set to copy for questions that don't come from the profile.
def donor_answers(form, person)
  donor = FormSubmission.joins(:form_response).where(form_responses: { form_id: form.id }, status: :active)
    .where.not(form_responses: { subject_id: person.id }).order(:submitted_at, :id).first
  return {} unless donor
  keys = form.answerable_questions.reject(&:person_field_id).map(&:key)
  donor.answers.slice(*keys)
end

def submit_form(form, person)
  access = FormAccess.new(person, person, form)
  return "not in the audience" unless form.in_audience?(person)
  response = form.response_for(person) || form.form_responses.create!(subject: person)
  submission = response.start_submission!(person)
  submission.update!(answers: submission.answers.merge(donor_answers(form, person)))
  errors = submission.submit!(person, access)
  return "missing #{errors.keys.join(', ')}" if errors.any?
  form.signature_questions.each do |question|
    next unless access.can_sign?(question)
    submission.reload.sign!(question, signer: person, typed_name: "#{person.first_name} #{person.last_name}", access: access,
      ip_address: "192.0.2.17", user_agent: "Mozilla/5.0 (demo browser)")
  end
  response.reload.status
end

# This season starts with the checklists' windows; meetings are the past events on a time clock period.
season_start = Checklist.active.minimum(:starts_on)&.beginning_of_day || Time.current.beginning_of_year
meetings = Event.where.not(time_clock_period_id: nil).where(start_time: season_start..Time.current).where("end_time < ?", Time.current).order(:start_time).to_a
# Forms that active checklist items list.
listed_form_ids = ChecklistItem.joins(:checklist).where(checklists: { status: Checklist.statuses[:active] }, kind: "form_complete")
  .flat_map { |item| Array(item.config["form_ids"]) }.uniq

admin = Person.joins(:user).find_by(users: { admin: true })

PERSONAS.each_with_index do |spec, index|
  say "#{spec[:first]} #{spec[:last]}"
  user = User.find_or_initialize_by(email: spec[:email])
  user.password = PASSWORD if user.new_record?
  user.admin = true if spec[:admin]
  user.save!
  PaperTrail.request.whodunnit = user.id
  person = Person.find_or_initialize_by(user: user)
  person.assign_attributes(first_name: spec[:first], last_name: spec[:last], display_name: "#{spec[:first]} #{spec[:last]}",
    gender: spec[:gender], shirt_size: spec[:shirt_size], birthday: Date.parse(spec[:birthday]), phone_number: format("(317) 555-01%02d", 90 + index),
    address: "#{1747 + index} Demo Way, West Lafayette, IN 47906")
  person.save!

  spec[:teams].each do |name, manager|
    team = Team.find_by(name: name)
    next say("team missing, skipped", name) unless team
    membership = Membership.find_or_initialize_by(person: person, team: team)
    membership.update!(manager: manager)
    say "member of #{name}", manager ? "manager" : "member"
  end
  person.reload

  spec[:badges].each do |name|
    badge = Badge.find_by(name: name)
    next say("badge missing, skipped", name) unless badge
    assignment = BadgeAssignment.find_or_initialize_by(person: person, badge: badge)
    say("badge", assignment.save ? name : "#{name} (#{assignment.errors.full_messages.to_sentence})")
  end

  Array(spec[:organizes]).each do |title|
    sheet = SignupSheet.find_by(title: title)
    next say("sheet missing, skipped", title) unless sheet
    SignupSheetOrganizer.find_or_create_by!(signup_sheet: sheet, person: person)
    say "organizes", title
  end

  # Two forms: open ones first.
  forms = Form.all.sort_by { |form| [ spec[:listed_forms] && listed_form_ids.exclude?(form.id) ? 1 : 0, form.closes_at && form.closes_at < Time.current ? 1 : 0, form.title ] }
  wanted = spec.fetch(:forms, 2)
  wanted = [ wanted, listed_form_ids.size ].max if spec[:listed_forms]
  submitted = 0
  forms.each do |form|
    break if submitted >= wanted
    next if FormResponse.exists?(form: form, subject: person)
    result = submit_form(form, person)
    say "form #{form.title}", result
    submitted += 1 if %w[complete waiting].include?(result.to_s)
  end

  # Check-ins at the latest past events of a type, this season.
  spec.fetch(:checkins, {}).each do |type_name, count|
    events = Event.joins(:event_type).where(event_types: { name: type_name }).where(start_time: season_start..Time.current).order(start_time: :desc).limit(count)
    events.each do |event|
      checkin = Checkin.find_or_initialize_by(person: person, event: event)
      checkin.created_by = person
      checkin.save!
    end
    say "check-ins at #{type_name}", events.size
  end

  # Punches over past meetings, every nth one. The periods take punches added by an admin, so one adds them.
  if spec[:attends]
    punched = 0
    meetings.each_with_index do |event, position|
      next unless (position % spec[:attends]).zero?
      punch = TimeClockPunch.new(person: person, time_clock_period: event.time_clock_period, start_time: event.start_time, end_time: event.end_time, created_by: admin)
      punch.save ? punched += 1 : say("punch skipped (#{event.name})", punch.errors.full_messages.to_sentence)
    end
    say "meeting punches", "#{punched} of #{meetings.size}"
  end

  # Two upcoming sign-ups on open sheets.
  placed = Signup.where(person: person).count
  SignupSlot.joins(:event).where("events.start_time > ?", Time.current).order("events.start_time", :id).each do |slot|
    break if placed >= spec.fetch(:signups, 2)
    next if Signup.exists?(signup_slot: slot, person: person)
    position = slot.signup_position
    signup = Signup.place!(slot: slot, person: person, signed_up_by: person, quantity: spec[:item_quantities] && !position.people? ? 1 : nil, answer: position.question.present? ? "Yes" : nil)
    say "sign-up", "#{position.signup_sheet.title}: #{position.name} (#{slot.event.start_time.to_date})"
    placed += 1
  rescue ActiveRecord::RecordInvalid => error
    next if error.record.is_a?(Signup)
    raise
  end
  say "sign-ups", placed
end

# Guardians, through the relationship type Concessions' count item pools on. An admin adds them,
# as the type needs a manager of both sides.
PERSONAS.each do |spec|
  next unless spec[:guardian_of]
  guardian = User.find_by!(email: spec[:email]).person
  type = RelationshipType.find(ChecklistItem.where(kind: "count").filter_map { _1.config["group_relationship_type_id"].presence }.first)
  spec[:guardian_of].each do |email|
    ward = User.find_by!(email: email).person
    relationship = Relationship.find_or_initialize_by(parent: guardian, child: ward, relationship_type: type)
    relationship.created_by = admin
    relationship.save!
    say "guardian of", ward.display_name
  end
end

# A sheet with a position that needs Outreach: Sam Student is covered and hasn't
# finished it, Demo Member isn't covered, and nothing on the sheet counts toward it.
outreach = Checklist.active.find_by("title LIKE ?", "Outreach%")
event = Event.joins(:event_type).where(event_types: { name: "Outreach" }).where("start_time > ?", Time.current).order(:start_time).first
if outreach && event
  sheet = SignupSheet.find_or_create_by!(title: "Outreach Booth Helpers") do |new_sheet|
    new_sheet.team = outreach.team
    new_sheet.status = "open"
    new_sheet.description = "Help at an outreach booth. Open to people who have finished their outreach."
    new_sheet.created_by_id = admin&.id
  end
  position = sheet.signup_positions.find_or_create_by!(name: "Booth Helper") { |new_position| new_position.capacity = 4 }
  position.signup_slots.find_or_create_by!(event: event)
  rule = position.signup_position_rules.find_or_initialize_by(kind: "checklist")
  rule.update!(checklist: outreach)
  say "sheet", "#{sheet.title}: #{position.name} needs #{outreach.title}"
else
  say "outreach checklist or upcoming Outreach event missing, sheet skipped"
end

# What the worker would do: bring every checklist's stored results up to date.
2.times { Checklist.active.find_each { |list| Checklists::Refresher.new(list, silent: true).call } } # twice: Travel Eligibility needs the others first
say "checklists refreshed", Checklist.active.count
PaperTrail.request.whodunnit = nil
