# A guardian for the family page: Dana (dana@) has two wards. Nora has a form
# due and a shift to claim; Jonah is all caught up. Their team sits outside the
# base org, so forms sent to everyone there don't reach them.
Hbr::SampleData.people "Dana Rivers", "Nora Rivers", "Jonah Rivers"

Hbr::SampleData.feature "feature/my-gatherpack-family" do |s|
  admin = s.login(:admin)
  dana = s.login!(:family_guardian, "dana", "Dana", "Rivers")
  nora = s.person!("Nora", "Rivers", birthday: s.clock.today - 13.years)
  jonah = s.person!("Jonah", "Rivers", birthday: s.clock.today - 15.years)

  parent_type = s.upsert!(RelationshipType, { parent_label: "Parent", child_label: "Child" }, permission: "added_by_manager", guardianship: "minor")
  [ nora, jonah ].each do |ward|
    next if Relationship.exists?(parent: dana, child: ward, relationship_type: parent_type)

    Relationship.create!(parent: dana, child: ward, relationship_type: parent_type, created_by: admin)
  end

  helpers = s.team!(:family_helpers, "Family Helpers", TeamType.find_or_create_by!(name: "Crew") { |type| type.icon = "people-group" }, "#2a7f62")
  [ nora, jonah ].each { |ward| s.member!(ward, helpers) }

  night = s.upsert!(Event, { name: "Family Helpers Night" }, event_type: EventType.find_or_create_by!(name: "Workday"), team: helpers,
    location: "Community Hall", start_time: s.clock.days_from_now(6, hour: 18), end_time: s.clock.days_from_now(6, hour: 20))

  form = s.upsert!(Form, { key: "family_helpers_contact" }, title: "Family Helpers Contact Card", team: helpers, status: "open", created_by: admin,
    respond_permission: "family", read_permission: "family", opens_at: s.clock.days_ago(3), closes_at: s.clock.days_from_now(9, hour: 23, min: 59))
  FormAudienceRule.find_or_create_by!(form: form, effect: "include", target_type: "team", team: helpers)
  s.upsert!(FormQuestion, { form: form, key: "best_time" }, position: 0, kind: "input", label: "Best time to reach you", data_type: "select",
    required: true, options: { "choices" => %w[Morning Afternoon Evening] })

  # Through the fill page's steps, so the status is what real use produces.
  form = Form.find(form.id)
  response = form.form_responses.find_or_initialize_by(subject: jonah)
  if response.new_record?
    response.save!
    access = FormAccess.new(dana, jonah, form)
    submission = response.start_submission!(dana)
    errors = submission.assign_answers({ "best_time" => "Evening" }, access)
    errors = submission.submit!(dana, access) if errors.empty? && submission.save!
    raise Hbr::SampleData::Error, "Contact card for Jonah: #{errors}" if errors.any?
  end

  sheet = s.upsert!(SignupSheet, { title: "Family Helpers Night" }, team: helpers, status: :open, created_by: admin,
    others_relationship_type_ids: [ parent_type.id ])
  SignupSheetEvent.find_or_create_by!(signup_sheet: sheet, event: night)
  position = s.upsert!(SignupPosition, { signup_sheet: sheet, name: "Setup" }, position: 0, kind: :people, capacity: 4)
  sheet.sync_slots!
  slot = position.signup_slots.find_by!(event: night)
  Signup.find_by(signup_slot: slot, person: jonah) || Signup.place!(slot: slot, person: jonah, signed_up_by: jonah)

  s.report "Dana (dana@) has Nora, with a form due and a shift to claim, and Jonah, all caught up"
  s.expect("Dana has two wards") { dana.wards.count == 2 }
  s.expect("Jonah's contact card is complete") { form.form_responses.find_by!(subject: jonah).reload.status == "complete" }
  s.expect("Nora hasn't answered her contact card") { !form.form_responses.exists?(subject: nora) }
  s.expect("Nora has a shift she can claim") { !slot.reload.full? && !Signup.exists?(signup_slot: slot, person: nora) }
end
