require_relative "person_fields_world"

# The person fields world plus helpers for forms. Forms default to the Pack
# team, so the audience is everyone with a membership in Pack, Den A, or
# Den B (students and their leaders, not parents or the health officer).
module FormsWorld
  include PersonFieldsWorld

  def create_world_form(title = "Meal Choices", team: @pack, respond: "family", read: "family", status: :open, **attributes)
    Form.create!(title: title, team: team, respond_permission: respond, read_permission: read, status: status, **attributes)
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
