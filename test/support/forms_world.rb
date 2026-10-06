require_relative "person_fields_world"

# The person fields world plus helpers for forms. Forms default to the Pack
# team, and to one audience rule including it, so the audience is everyone
# with a membership in Pack, Den A, or Den B (students and their leaders, not
# parents or the health officer). Pass include: [] for a form with no rules.
module FormsWorld
  include PersonFieldsWorld

  def create_world_form(title = "Meal Choices", team: @pack, include: [ team ], respond: "family", read: "family", status: :open, **attributes)
    form = Form.create!(title: title, team: team, respond_permission: respond, read_permission: read, status: :draft, **attributes.except(:completion_badge))
    include.each { |target| add_rule(form, target) }
    form.update!(status: status, **attributes.slice(:completion_badge))
    form
  end

  def add_rule(form, target, effect: :include, include_managers: true)
    attributes = case target
    when Team then { target_type: :team, team: target, include_managers: include_managers }
    when Badge then { target_type: :badge, badge: target }
    when Person then { target_type: :person, person: target }
    end
    form.form_audience_rules.create!(effect: effect, **attributes).tap { form.form_audience_rules.reset }
  end

  def add_signature(form, label = "Consent", signer: "guardian_if_minor", **attributes)
    form.form_questions.create!(kind: :signature, label: label, signer: signer, **attributes)
  end

  def sign(form, subject, as:, question: nil)
    submission = form.response_for(person(subject)).open_submission
    question ||= form.signature_questions.first
    signer = person(as)
    error = submission.sign!(question, signer: signer, typed_name: "#{signer.first_name} #{signer.last_name}", access: FormAccess.new(signer, person(subject), form))
    raise "sign error: #{error}" if error
    submission.reload
  end

  def add_choice(form, label, choices, **attributes)
    form.form_questions.create!(kind: :input, label: label, data_type: :select, choices: choices, **attributes)
  end

  def add_profile_question(form, field, mode, **attributes)
    form.form_questions.create!(kind: :input, label: field.name, person_field: field, profile_mode: mode, **attributes)
  end

  def respond(form, subject, as:, answers:, submit: true)
    access = FormAccess.new(person(as), person(subject), form)
    response = form.form_responses.find_or_create_by!(subject: person(subject))
    submission = response.start_submission!(person(as))
    errors = submission.assign_answers(answers, access)
    raise "answer errors: #{errors}" if errors.any?
    submission.save!
    response.sync_status!
    if submit
      errors = submission.submit!(person(as), access)
      raise "submit errors: #{errors}" if errors.any?
    end
    submission.reload
  end
end
