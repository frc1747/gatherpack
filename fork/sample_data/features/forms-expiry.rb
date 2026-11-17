# Forms whose responses expire: a "Yearly Physical" good for 12 months after
# signing, with Grace's signed recently ("Good until ...") and Sam's signed
# 13 months ago (expired, so it needs re-confirmation), and a "Facility Use
# Agreement" that expires for everyone on a date a month from now. Sam's
# signing date is moved back on every run, so his stays expired.
Hbr::SampleData.feature "feature/forms-expiry" do |s|
  s.enable_feature :forms
  admin = s.login(:admin)
  youth = s.team(:youth)

  form = lambda do |key, attrs|
    record = s.upsert!(Form, { key: key }, { created_by: admin, team: youth, status: "open" }.merge(attrs))
    FormAudienceRule.find_or_create_by!(form: record, effect: "include", target_type: "team", team: youth)
    Form.find(record.id)
  end
  # Answers and submits as the admin, once per person.
  respond = lambda do |record, subject, answers|
    response = record.form_responses.find_or_create_by!(subject: subject)
    next response if response.active_submission

    access = FormAccess.new(admin, subject, record)
    submission = response.start_submission!(admin)
    errors = submission.assign_answers(answers, access)
    errors = submission.submit!(admin, access) if errors.empty? && submission.save!
    raise Hbr::SampleData::Error, "#{record.title} for #{subject.first_name}: #{errors}" if errors.any?

    response.reload
  end

  physical = form.call("yearly_physical", {
    title: "Yearly Physical", valid_for_months: 12, expires_on: nil,
    description: "Confirm a physical on file. It's good for a year after you sign."
  })
  s.upsert!(FormQuestion, { form: physical, key: "physical_on_file" },
    position: 0, kind: "input", label: "Physical on file", data_type: "select", required: true, options: { "choices" => %w[ Yes No ] })
  physical = Form.find(physical.id)

  grace = respond.call(physical, s.person("Grace"), { "physical_on_file" => "Yes" })
  sam = respond.call(physical, s.person("Sam"), { "physical_on_file" => "Yes" })
  signed = s.clock.days_ago(395)
  sam.active_submission.update_columns(submitted_at: signed, activated_at: signed)
  sam.sync_status!

  agreement = form.call("facility_use_agreement", {
    title: "Facility Use Agreement", expires_on: s.clock.date(30), valid_for_months: nil,
    description: "The building rules for this year. Replaced on the date below."
  })
  s.upsert!(FormQuestion, { form: agreement, key: "agree" },
    position: 0, kind: "input", label: "I agree to the building rules", data_type: "boolean", required: true)
  respond.call(Form.find(agreement.id), s.person("Grace"), { "agree" => "true" })

  s.report "Yearly Physical: Grace #{grace.reload.expiry_summary.downcase}, Sam expired; Facility Use Agreement expires #{agreement.expires_on}"
  s.expect("Grace's physical is complete with an expiry") { grace.reload.complete? && grace.expires_at.present? }
  s.expect("Sam's physical expired") { sam.reload.needs_reconfirmation? && sam.reconfirmation_reason == :expired }
end
