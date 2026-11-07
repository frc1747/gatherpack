# Adds two form items to "Trip Eligibility" (feature/checklists) and a form
# that asks the people the checklist covers:
#
# - "Parent consent" reads Parent Consent (feature/forms): Grace is done,
#   Kate is almost (waiting for Paula's signature), Olive is not yet (needs
#   confirming again after a profile change). Nina, an applicant on no team,
#   isn't asked by that form, so she is not yet and the checklist lists it
#   as a problem.
# - "Trip medical release" reads Trip Medical Release, signed within the
#   last 12 months. Its audience is "everyone Trip Eligibility covers", so
#   Nina is asked too. Chloe has signed it; with forms expiry present it is
#   good for 12 months and shows "Good until <date>".
Hbr::SampleData.feature "feature/checklists-forms" do |s|
  admin = s.login(:admin)
  checklist = Checklist.find_by!(title: "Trip Eligibility")
  consent = Form.find_by!(key: "parent_consent")

  release = s.upsert!(Form, { key: "trip_medical_release" },
    title: "Trip Medical Release", team: s.team(:youth), created_by: admin,
    respond_permission: "family", read_permission: "family",
    description: "Allergies, medicines and who to call, for everyone going on the spring trip.")
  release.update!(valid_for_months: 12) if release.respond_to?(:valid_for_months=)
  s.upsert!(FormQuestion, { form: release, key: "accurate" }, position: 1, kind: "acknowledgment",
    label: "The medical details on my profile are up to date.", required: true)
  FormAudienceRule.find_or_create_by!(form: release, effect: "include", target_type: "checklist", checklist: checklist, checklist_match: "covered")
  release.update!(status: "open") unless release.open?

  chloe = s.person("Chloe")
  response = release.form_responses.find_or_create_by!(subject: chloe)
  unless response.active_submission
    access = FormAccess.new(chloe, chloe, release)
    submission = response.start_submission!(chloe)
    submission.assign_answers({ "accurate" => "1" }, access)
    submission.save!
    errors = submission.submit!(chloe, access)
    raise Hbr::SampleData::Error, "Trip Medical Release for Chloe: #{errors}" if errors.any?
  end

  item = lambda do |label, position, config, **attrs|
    record = ChecklistItem.find_or_initialize_by(checklist: checklist, label: label)
    record.assign_attributes({ kind: "form_complete", position: position }.merge(attrs))
    record.config_params = config
    record.save! if record.new_record? || record.changed?
    record
  end
  consent_item = item.call("Parent consent", 6, { form_ids: [ consent.id ] })
  release_item = item.call("Trip medical release", 7, { form_ids: [ release.id ] }, starts_within_amount: 12, starts_within_unit: "months")

  Checklists::Refresher.new(checklist.reload, silent: true).call
  status = ->(record, first) { checklist.checklist_results.find_by(item: record, person: s.person(first))&.status }
  s.report "Trip Eligibility: Parent consent and Trip medical release items"
  s.expect("Grace's consent is done") { status.call(consent_item, "Grace") == "met" }
  s.expect("Kate's consent is almost, waiting for Paula") { status.call(consent_item, "Kate") == "pending" }
  s.expect("Nina isn't asked Parent Consent, and it's a problem") do
    status.call(consent_item, "Nina") == "not_met" && checklist.problems.any? { |problem| problem.include?("aren't asked Parent Consent") || problem.include?("isn't asked Parent Consent") }
  end
  s.expect("Nina is asked Trip Medical Release through the checklist") { release.reload.in_audience?(s.person("Nina")) }
  s.expect("Chloe's medical release is done") { status.call(release_item, "Chloe") == "met" }
end
