# Forms for the MCP forms tools, on top of McpWorld (include both; call
# build_mcp_world first). Turns the forms and person fields features on for each
# test.
#
#   "Lunch" (Alpha, open, respond and read at family level) asks Alpha: alpha_manager,
#   alpha_member and ward. Questions: Sandwich (choice), Notes (text, readable by
#   leaders and the person only) and Allergies (a person field only the subject
#   and admins read). alpha_member answered Slim 4 / "no onions" / peanut, ward
#   answered through guardian (Big John), alpha_manager has not answered.
#   coordinator (Beta, no team ties to Alpha) holds the "Form Coordinator" badge,
#   which has a read grant on Lunch. Cross, Named, Private and Mixed cover partial reach
#   (see build_mcp_forms_world). "Trip" is a draft on Beta, "Old" is archived on Alpha.
module McpFormsWorld
  def self.included(base)
    base.setup { @restore_forms_features = apply_settings(feature_forms: "true", feature_person_fields: "true") }
    base.teardown { @restore_forms_features&.call }
  end

  def build_mcp_forms_world
    @parent_of.update!(guardianship: :minor)
    @people[:coordinator] = create_world_person("Coordinator", @beta)
    @coordinator_badge = create_world_badge("Form Coordinator")
    BadgeAssignment.create!(badge: @coordinator_badge, person: person(:coordinator))

    @allergies = PersonField.create!(name: "Allergies", data_type: :string, read_permission: "self", write_permission: "self")
    person(:alpha_member).set_field_value(@allergies, "peanut")

    @lunch = create_world_form("Lunch", @alpha)
    @sandwich = @lunch.form_questions.create!(kind: :input, label: "Sandwich", data_type: :select, choices: [ "Slim 4", "Big John" ])
    @notes = @lunch.form_questions.create!(kind: :input, label: "Notes", data_type: :string, read_permission: "self_and_leaders")
    @allergy_question = @lunch.form_questions.create!(kind: :input, label: "Allergies", person_field: @allergies, profile_mode: :prefill)
    @lunch.form_badge_grants.create!(badge: @coordinator_badge, access: :read)

    respond_to_form(@lunch, :alpha_member, as: :alpha_member, answers: { "sandwich" => "Slim 4", "notes" => "no onions", "allergies" => "peanut" })
    respond_to_form(@lunch, :ward, as: :guardian, answers: { "sandwich" => "Big John" })

    @lunch.update!(opens_at: 2.days.ago)

    # Asks Alpha and Beta, so Alpha's manager can read only the Alpha half; alpha_member holds
    # a read grant limited to Alpha people.
    @alpha_badge = create_world_badge("Alpha Coordinator", team: @alpha)
    BadgeAssignment.create!(badge: @alpha_badge, person: person(:alpha_member))
    @cross = create_world_form("Cross", @alpha, include: [ @alpha, @beta ])
    @cross_choice = @cross.form_questions.create!(kind: :input, label: "Choice", data_type: :string)
    @cross.form_badge_grants.create!(badge: @alpha_badge, access: :read)
    @medical = @cross.form_questions.create!(kind: :input, label: "Medical", data_type: :string, read_permission: "admin")
    %i[ alpha_member beta_member badge_holder ].each { |name| respond_to_form(@cross, name, as: name, answers: { "choice" => name.to_s }) }

    # Asks one Beta member by name, who has answered.
    @named = create_world_form("Named", @alpha, include: [])
    @named.form_audience_rules.create!(effect: :include, target_type: :person, person: person(:beta_member))
    @named.form_questions.create!(kind: :input, label: "Pick", data_type: :string)
    respond_to_form(@named, :beta_member, as: :beta_member, answers: { "pick" => "x" })

    # Only the person themselves can read their response.
    @private = create_world_form("Private", @alpha)
    @private.update!(respond_permission: "self", read_permission: "self")
    @private.form_questions.create!(kind: :input, label: "Secret", data_type: :string)
    respond_to_form(@private, :alpha_member, as: :alpha_member, answers: { "secret" => "mine" })

    # A complete, a withdrawn, a draft-only and a no-longer-asked response.
    @mixed = create_world_form("Mixed", @alpha)
    @mixed.form_questions.create!(kind: :input, label: "Pick", data_type: :string)
    respond_to_form(@mixed, :alpha_manager, as: :alpha_manager, answers: { "pick" => "a" })
    respond_to_form(@mixed, :alpha_member, as: :alpha_member, answers: { "pick" => "b" }).withdraw!
    respond_to_form(@mixed, :ward, as: :guardian, answers: { "pick" => "c" }, submit: false)
    rule = @mixed.form_audience_rules.create!(effect: :include, target_type: :person, person: person(:beta_member))
    respond_to_form(@mixed, :beta_member, as: :beta_member, answers: { "pick" => "d" })
    rule.destroy!
    @mixed.form_audience_rules.reset
    @mixed.form_responses.each(&:sync_status!)

    @trip = create_world_form("Trip", @beta, status: :draft, include: [])
    @old = create_world_form("Old", @alpha, status: :archived)
  end

  def create_world_form(title, team, status: :open, include: [ team ])
    form = Form.create!(title: title, team: team, respond_permission: "family", read_permission: "family", status: :draft)
    include.each { |target| form.form_audience_rules.create!(effect: :include, target_type: :team, team: target) }
    form.form_audience_rules.reset
    form.update!(status: status) unless status == :draft
    form
  end

  def respond_to_form(form, subject, as:, answers:, submit: true)
    access = FormAccess.new(person(as), person(subject), form)
    response = form.form_responses.find_or_create_by!(subject: person(subject))
    submission = response.start_submission!(person(as))
    errors = submission.assign_answers(answers, access)
    raise "answer errors: #{errors}" if errors.any?

    submission.save!
    return submission unless submit

    errors = submission.submit!(person(as), access)
    raise "submit errors: #{errors}" if errors.any?

    submission.reload
  end
end
