# Adds the documentation personas (Demo Member, Demo Lead, Demo Mentor) to an
# anonymized demo database. Run by bin/fork-make-demo-db after anonymize.rb.
# Everything goes through the models, as if each persona had done it.
#
# Env: DEMO_PASSWORD.
require_relative "guard"

DemoDb.guard!
PASSWORD = ENV["DEMO_PASSWORD"].presence || "password123"

PERSONAS = [
  { first: "Demo", last: "Member", email: "demo.member@example.invalid", gender: "F", shirt_size: "M", birthday: "2011-03-14",
    teams: { "Team 1747 - Class of 2029" => false },
    badges: [ "2027 Season Safety Training Complete", "2027 FIRST Registered", "2027 Season Rookie" ] },
  { first: "Demo", last: "Lead", email: "demo.lead@example.invalid", gender: "M", shirt_size: "L", birthday: "2009-05-02",
    teams: { "Team 1747 - Class of 2027" => false, "Team 1747 - Student Leadership" => true },
    badges: [ "2027 Season Safety Training Complete", "2027 FIRST Registered", "2027 FIRST Consent Signed", "Student Form Creator" ] },
  { first: "Demo", last: "Mentor", email: "demo.mentor@example.invalid", gender: "F", shirt_size: "L", birthday: "1983-09-21",
    teams: { "Mentors" => true, "Team 1747 - Student Leadership" => true },
    badges: [ "2027 Season TSC Mentor Requirements", "Events Coordinator", "Sign-up Organizer", "2027 Season FIRST Mentor Ready Certified" ],
    organizes: [ "Concessions Stocking" ] }
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

PERSONAS.each_with_index do |spec, index|
  say "#{spec[:first]} #{spec[:last]}"
  user = User.find_or_initialize_by(email: spec[:email])
  user.password = PASSWORD if user.new_record?
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
  forms = Form.all.sort_by { |form| [ form.closes_at && form.closes_at < Time.current ? 1 : 0, form.title ] }
  submitted = 0
  forms.each do |form|
    break if submitted == 2
    next if FormResponse.exists?(form: form, subject: person)
    result = submit_form(form, person)
    say "form #{form.title}", result
    submitted += 1 if %w[complete waiting].include?(result.to_s)
  end

  # Two upcoming sign-ups on open sheets.
  placed = Signup.where(person: person).count
  SignupSlot.joins(:event).where("events.start_time > ?", Time.current).order("events.start_time", :id).each do |slot|
    break if placed >= 2
    next if Signup.exists?(signup_slot: slot, person: person)
    position = slot.signup_position
    signup = Signup.place!(slot: slot, person: person, signed_up_by: person, answer: position.question.present? ? "Yes" : nil)
    say "sign-up", "#{position.signup_sheet.title}: #{position.name} (#{slot.event.start_time.to_date})"
    placed += 1
  rescue ActiveRecord::RecordInvalid => error
    next if error.record.is_a?(Signup)
    raise
  end
  say "sign-ups", placed
end
PaperTrail.request.whodunnit = nil
