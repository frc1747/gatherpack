# Forms in each state: an open season form half answered, a consent form
# with a guardian signature (complete, waiting for a guardian, and needing
# re-confirmation after a profile change), an event form with an intent
# question, and a closed form with answers still missing. Responses go
# through the same steps as the fill page, so statuses and signatures are
# what real use produces. Needs the person fields layer (guardians, fields).
Hbr::SampleData.feature "feature/forms" do |s|
  s.enable_feature :forms
  admin = s.login(:admin)
  paula = s.login(:parent1)
  owen = s.login(:parent2)

  form = lambda do |key, attrs, teams|
    record = s.upsert!(Form, { key: key }, { created_by: admin }.merge(attrs))
    teams.each { |team| FormAudienceRule.find_or_create_by!(form: record, effect: "include", target_type: "team", team: team) }
    record
  end
  question = lambda do |record, key, position, attrs|
    s.upsert!(FormQuestion, { form: record, key: key }, { position: position }.merge(attrs))
  end
  # Answers and submits as `actor`, once per person: later runs leave
  # existing responses alone.
  respond = lambda do |record, subject, actor, answers|
    # Building the form caches its question list and audience before every
    # question and audience rule exists, so answer through a fresh copy.
    record = Form.find(record.id)
    response = record.form_responses.find_or_initialize_by(subject: subject)
    next response.active_submission || response.open_submission if response.persisted?

    response.save!
    access = FormAccess.new(actor, subject, record)
    submission = response.start_submission!(actor)
    errors = submission.assign_answers(answers, access)
    errors = submission.submit!(actor, access) if errors.empty? && submission.save!
    raise Hbr::SampleData::Error, "#{record.title} for #{subject.first_name}: #{errors}" if errors.any?

    submission.reload
  end
  sign = lambda do |submission, signer|
    next unless submission&.pending?

    signature = submission.form.signature_questions.first
    error = submission.sign!(signature, signer: signer, typed_name: "#{signer.first_name} #{signer.last_name}",
      access: FormAccess.new(signer, submission.subject, submission.form))
    raise Hbr::SampleData::Error, "#{submission.form.title}: #{error}" if error
  end
  people = ->(team) { team.descendant_people.where(user_id: nil).order(:last_name, :first_name).to_a }

  # Season form: open, due in two weeks, about half answered.
  meals = form.call("meal_choices", {
    title: "Meal Choices", team: s.team(:root), status: "open", totals_visibility: "audience",
    description: "Pick your lunch for workdays this season.",
    opens_at: s.clock.days_ago(7), closes_at: s.clock.days_from_now(14, hour: 23, min: 59)
  }, [ s.team(:root) ])
  sandwiches = %w[Turkey Ham Veggie]
  cookies = [ "Chocolate Chip", "Oatmeal", "Sugar" ]
  question.call(meals, "sandwich", 0, kind: "input", label: "Sandwich", data_type: "select", required: true, options: { "choices" => sandwiches })
  question.call(meals, "cookie", 1, kind: "input", label: "Cookie", data_type: "select", options: { "choices" => cookies })
  question.call(meals, "allergies", 2, kind: "input", label: "Allergies", person_field: PersonField.find_by!(key: "allergies"),
    profile_mode: "update_profile")
  people.call(s.team(:root)).each_with_index do |person, i|
    respond.call(meals, person, admin, { "sandwich" => sandwiches[i % 3], "cookie" => cookies[i % 3] }) if i.even?
  end
  respond.call(meals, s.login(:member), s.login(:member), { "sandwich" => "Veggie" })

  # Consent form: a guardian signs; completing it awards Consent Signed.
  consent_badge = s.upsert!(Badge, { name: "Consent Signed" },
    badge_type: BadgeType.find_by!(name: "Certification"), team: s.team(:youth), permission: "added_by_admin", color: "#2ec27e", short: "file-signature")
  consent = form.call("parent_consent", {
    title: "Parent Consent", team: s.team(:youth), status: "open", completion_badge: consent_badge,
    reconfirm_on_profile_change: true, leader_todo: true,
    description: "Every Youth Program member needs a signed consent form before the campout.",
    opens_at: s.clock.days_ago(10), closes_at: s.clock.days_from_now(21, hour: 23, min: 59)
  }, [ s.team(:youth) ])
  question.call(consent, "intro", 0, kind: "statement", body: "Please review your child's medical notes and sign below.")
  question.call(consent, "medical_notes", 1, kind: "input", label: "Medical Notes", person_field: PersonField.find_by!(key: "medical_notes"),
    profile_mode: "update_profile")
  question.call(consent, "code_of_conduct", 2, kind: "acknowledgment", label: "I have read the Youth Program code of conduct.", required: true)
  question.call(consent, "guardian_signature", 3, kind: "signature", label: "Parent or guardian signature", signer: "guardian")

  grace = s.person("Grace")
  kate = s.person("Kate")
  olive = s.person("Olive")
  sign.call(respond.call(consent, grace, paula, { "code_of_conduct" => "1" }), paula)     # complete
  respond.call(consent, kate, admin, { "code_of_conduct" => "1" })                        # waiting for a guardian
  if !consent.form_responses.find_by(subject: olive)
    sign.call(respond.call(consent, olive, owen, { "code_of_conduct" => "1" }), owen)
    # The profile changes after signing, so the form asks for re-confirmation.
    olive.assign_field_values({ "medical_notes" => "Seasonal asthma. New inhaler prescribed." }, acting: admin)
    olive.save!
  end

  # Event form: are you coming to the campout?
  campout = Event.find_by!(name: "Youth Campout")
  rsvp = form.call("youth_campout_rsvp", {
    title: "Youth Campout: Are You Coming?", team: s.team(:youth), status: "open", event: campout,
    opens_at: s.clock.days_ago(3), closes_at: campout.start_time
  }, [ s.team(:youth) ])
  question.call(rsvp, "coming", 0, kind: "intent", label: "Are you coming?", required: true)
  question.call(rsvp, "can_drive", 1, kind: "input", label: "Can a parent drive?", data_type: "boolean")
  respond.call(rsvp, grace, paula, { "coming" => "Yes", "can_drive" => "1" })
  respond.call(rsvp, olive, owen, { "coming" => "Yes" })
  respond.call(rsvp, s.person("Chloe"), admin, { "coming" => "Maybe" })
  respond.call(rsvp, s.person("Sam"), admin, { "coming" => "No" })

  # Closed past its deadline with answers still missing; leaders can still
  # enter late answers.
  shirts = form.call("tshirt_order", {
    title: "Volunteer T-Shirt Order", team: s.team(:operations), status: "closed", late_entry: "leaders",
    opens_at: s.clock.days_ago(30), closes_at: s.clock.days_ago(2, hour: 23, min: 59)
  }, [ s.team(:operations) ])
  sizes = %w[S M L XL]
  question.call(shirts, "size", 0, kind: "input", label: "Shirt size", data_type: "select", required: true, options: { "choices" => sizes })
  shirts.update!(status: "open") if shirts.form_responses.none?
  people.call(s.team(:operations)).first(6).each_with_index { |person, i| respond.call(shirts, person, admin, { "size" => sizes[i % 4] }) }
  shirts.update!(status: "closed")

  # Form creators: Chloe (Youth Program lead) can make event polls for her team.
  creator = s.upsert!(Badge, { name: "Form Creator" },
    badge_type: BadgeType.find_by!(name: "Certification"), team: nil, permission: "added_by_admin", color: "#613583", short: "pen")
  BadgeAssignment.find_or_create_by!(badge: creator, person: s.person("Chloe"))
  s.setting :forms_creator_badge, "Form Creator"

  s.report "#{Form.count} forms, #{FormResponse.count} responses; Parent Consent: Grace complete, Kate waiting for a guardian, Olive needs re-confirmation"
  status = ->(record, person) { record.form_responses.find_by!(subject: person).reload.status }
  s.expect("Grace's consent is complete") { status.call(consent, grace) == "complete" }
  s.expect("Kate's consent waits for a guardian") { status.call(consent, kate) == "waiting" }
  s.expect("Olive's consent needs re-confirmation") { status.call(consent, olive) == "needs_reconfirmation" }
  s.expect("Grace has the Consent Signed badge") { grace.badges.include?(consent_badge) }
end
